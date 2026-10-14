/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Ultrasound (app 'ultrasound')           module: ultrasound
   eFAST scan on a live B-mode image, treatment plan, ultrasound-guided
   pericardiocentesis, chest drain (3D close-up, core/nza3d.js) and needle
   decompression.

   Part 1 · NZUS — the imaging engine (also used by screen.html, the cart DUI)
     NZUS.BMode(canvas, { seed, lines, samples })  → engine
         .set({ depth, gain, focus, frozen, contact, q, shift, vis, scene, needle, rr, hr })
         .frame(dtSeconds)          simulate + draw (skips work while frozen)
         .toPx(x, z) → [px, py]     world cm → canvas px     .fromPx(px, py) → [x, z] | null
         .mline(h) → Float32Array   centre scan line resampled (M-mode column)
         .needlePath() → { sac, wall, tip, hit }   (pericardiocentesis read-out)
     NZUS.scene(win, params, seed) → scene for 'ruq' 'luq' 'pelvis' 'cardiac' 'lung_r' 'lung_l'
                                     'bowel' (no window) 'air' (probe off the skin)
       scene.prep(st) per frame · scene.echo(x, z, out, st) per sample · scene.labels(st)
     World units: centimetres. x = lateral (image left = probe marker side), z = depth below
     the probe face. Physics: Rayleigh speckle (coherent sum, anisotropic PSF), ray-marched
     attenuation (bone / air shadows, enhancement behind fluid), TGC, log compression,
     focal zone, persistence.
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const G = (d, w) => Math.exp(-(d * d) / (w * w));
  function rng(seed) {
    let a = (seed >>> 0) || 0x9e3779b9;
    return () => {
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const gauss = r => { let u = 0; for (let i = 0; i < 6; i++) u += r(); return (u - 3) * 1.4142; };

  /* ─────────── speckle: |complex gaussian| after an anisotropic PSF → Rayleigh grains ─────────── */
  const SN = 256, SM = SN - 1;
  function blur1(src, dst, rad, horiz, N = SN) {
    const w = 2 * rad + 1, M = N - 1;
    for (let j = 0; j < N; j++) {
      let acc = 0;
      for (let k = -rad; k <= rad; k++) acc += horiz ? src[j * N + ((k + N) & M)] : src[((k + N) & M) * N + j];
      for (let i = 0; i < N; i++) {
        if (horiz) dst[j * N + i] = acc / w; else dst[i * N + j] = acc / w;
        const add = (i + rad + 1) & M, rem = (i - rad + N) & M;
        acc += horiz ? src[j * N + add] - src[j * N + rem] : src[add * N + j] - src[rem * N + j];
      }
    }
  }
  const SPECKLE = {};
  function speckle(seed) {
    if (SPECKLE[seed]) return SPECKLE[seed];
    const r = rng(seed), n = SN * SN;
    const re = new Float32Array(n), im = new Float32Array(n), t = new Float32Array(n);
    for (let i = 0; i < n; i++) { re[i] = gauss(r); im[i] = gauss(r); }
    blur1(re, t, 2, true); blur1(t, re, 1, false);
    blur1(im, t, 2, true); blur1(t, im, 1, false);
    const out = new Float32Array(n);
    let sum = 0;
    for (let i = 0; i < n; i++) { const m = Math.sqrt(re[i] * re[i] + im[i] * im[i]); out[i] = m; sum += m; }
    const k = n / sum;
    for (let i = 0; i < n; i++) out[i] *= k;
    SPECKLE[seed] = out;
    return out;
  }
  function sp(S, u, v) {
    const iu = Math.floor(u), iv = Math.floor(v), fu = u - iu, fv = v - iv;
    const x0 = iu & SM, y0 = iv & SM, x1 = (x0 + 1) & SM, y1 = (y0 + 1) & SM;
    const a = S[y0 * SN + x0], b = S[y0 * SN + x1], c = S[y1 * SN + x0], d = S[y1 * SN + x1];
    return a + (b - a) * fu + (c - a) * fv + (a - b - c + d) * fu * fv;
  }
  // smooth value noise in -1..1 (organ outlines, texture, haze); vnoise = 0..2 (mean 1)
  const NN = 128, NM = NN - 1;
  const NOI = (() => {
    const r = rng(77), n = NN * NN;
    let a = new Float32Array(n), t = new Float32Array(n);
    for (let i = 0; i < n; i++) a[i] = r() * 2 - 1;
    for (let pass = 0; pass < 3; pass++) { blur1(a, t, 3, true, NN); blur1(t, a, 3, false, NN); }
    let mx = 0;
    for (let i = 0; i < n; i++) mx = Math.max(mx, Math.abs(a[i]));
    for (let i = 0; i < n; i++) a[i] /= mx;
    return a;
  })();
  function snoise(x, z) {
    const u = x * 9 + 300.5, v = z * 9 + 700.5;
    const iu = Math.floor(u), iv = Math.floor(v), fu = u - iu, fv = v - iv;
    const x0 = iu & NM, y0 = iv & NM, x1 = (x0 + 1) & NM, y1 = (y0 + 1) & NM;
    const a = NOI[y0 * NN + x0], b = NOI[y0 * NN + x1], c = NOI[y1 * NN + x0], d = NOI[y1 * NN + x1];
    return a + (b - a) * fu + (c - a) * fv + (a - b - c + d) * fu * fv;
  }
  const vnoise = (x, z) => 1 + snoise(x * 0.5, z * 0.5) * 0.9;
  // two decorrelated channels in one lookup (organic outline warps): writes W2[0], W2[1]
  const W2 = new Float32Array(2);
  function warp2(x, z) {
    const u = x * 9 + 300.5, v = z * 9 + 700.5;
    const iu = Math.floor(u), iv = Math.floor(v), fu = u - iu, fv = v - iv;
    const x0 = iu & NM, y0 = iv & NM, x1 = (x0 + 1) & NM, y1 = (y0 + 1) & NM;
    const xo = (x0 + 64) & NM, xo1 = (x1 + 64) & NM;
    const a = NOI[y0 * NN + x0], b = NOI[y0 * NN + x1], c = NOI[y1 * NN + x0], d = NOI[y1 * NN + x1];
    const a2 = NOI[y0 * NN + xo], b2 = NOI[y0 * NN + xo1], c2 = NOI[y1 * NN + xo], d2 = NOI[y1 * NN + xo1];
    const k = fu * fv;
    W2[0] = a + (b - a) * fu + (c - a) * fv + (a - b - c + d) * k;
    W2[1] = a2 + (b2 - a2) * fu + (c2 - a2) * fv + (a2 - b2 - c2 + d2) * k;
  }
  // specular strength of an interface: bright where the beam hits it square on, dim where it grazes
  const R0A = 2.6;
  function spec(x, z, nx, nz) {
    const bx = x, bz = z + R0A, bl = Math.hypot(bx, bz) || 1, nl = Math.hypot(nx, nz) || 1;
    const d = Math.abs((nx * bx + nz * bz) / (bl * nl));
    return 0.18 + 0.82 * d * d * d;
  }

  /* ─────────── shape helpers (all in cm) ─────────── */
  function ellN(x, z, cx, cz, rx, rz, cs, sn) {
    const dx = x - cx, dz = z - cz;
    const u = dx * cs + dz * sn, v = -dx * sn + dz * cs;
    return Math.sqrt((u / rx) * (u / rx) + (v / rz) * (v / rz));
  }
  function ellUV(x, z, cx, cz, cs, sn, out) {
    const dx = x - cx, dz = z - cz;
    out[0] = dx * cs + dz * sn; out[1] = -dx * sn + dz * cs;
    return out;
  }
  // skin → subcutaneous fat (septa) → muscle (striations) → fascia. true if the sample is in the wall.
  function wall(x, z, o, fat, mus) {
    if (z < 0) { o.e = 0; o.a = 0; return true; }
    if (z < 0.18) { o.e = 1.25; o.a = 0.4; o.s = 0.45; o.id = 1; return true; }
    const zf = 0.18 + fat;
    if (z < zf) {
      const f1 = G(z - 0.18 - fat * (0.38 + 0.12 * Math.sin(x * 1.7)), 0.045);
      const f2 = G(z - 0.18 - fat * (0.72 + 0.08 * Math.sin(x * 1.13 + 2)), 0.04);
      o.e = 0.2 + 0.8 * (f1 + f2); o.a = 0.1; o.s = 0.85; o.id = 2; return true;
    }
    const zm = zf + mus;
    if (z < zm) {
      const fas = G(z - zf, 0.055) * 1.3;
      const str = 0.5 + 0.5 * Math.sin((z - zf) * 24 + Math.sin(x * 0.8) * 1.4);
      o.e = 0.3 + 0.3 * str * str * str + fas; o.a = 0.24; o.s = 0.72; o.id = 3; return true;
    }
    if (z < zm + 0.12) { o.e = 1.35; o.a = 0.26; o.s = 0.4; o.id = 4; return true; }
    return false;
  }
  // rib / bone in cross-section: bright cortex (angle dependent), full acoustic shadow
  const shadowBone = o => { o.e = 0.01; o.a = 60; o.s = 0.2; o.id = 5; };
  function bone(x, z, o, cx, cz, r) {
    const dx = x - cx, dz = z - cz, d = Math.hypot(dx, dz) - r;
    if (d > 0.1) return false;
    if (d > -0.15) { o.e = 2.8 * spec(x, z, dx, dz); o.a = 9; o.s = 0.3; o.id = 5; return true; }
    shadowBone(o);
    return true;
  }
  // bowel loop with gas: hypoechoic wall, bright gas line on the near side, dirty shadow behind
  function gasLoop(x, z, o, cx, cz, r, t) {
    const dx = x - cx, dz = (z - cz) * 1.3;
    if (dx > r * 1.35 + 0.3 || dx < -r * 1.35 - 0.3 || dz > r * 1.35 + 0.3 || dz < -r * 1.35 - 0.3) return false;
    const d = Math.hypot(dx, dz) - r * (1 + 0.22 * snoise(cx * 3 + Math.atan2(dz, dx) * 0.6, cz * 3));
    if (d > 0.24) return false;
    if (d > 0.06) { o.e = 0.55; o.a = 0.25; o.s = 0.85; o.id = 10; return true; }
    if (dz < 0 && d > -0.24) { o.e = 2.3 * (0.75 + 0.25 * Math.sin(t * 2.3 + x * 3)) * spec(x, z, dx, dz); o.a = 3.2; o.s = 0.6; o.id = 11; return true; }
    o.e = 0.6 + 0.4 * Math.sin(z * 12 + t * 1.6) * Math.sin(x * 2.7 + 1); o.a = 0.7; o.s = 0.9; o.id = 11; return true;
  }
  // liver / spleen parenchyma with a few vessels (cx, cz, r, elongation)
  function parenchyma(x, z, o, base, vessels, id) {
    for (let i = 0; i < vessels.length; i += 4) {
      const n = Math.hypot((x - vessels[i]) / (vessels[i + 2] * vessels[i + 3]), (z - vessels[i + 1]) / vessels[i + 2]);
      if (n < 1.25) {
        if (n > 0.9) { o.e = base + 0.55 * spec(x, z, x - vessels[i], z - vessels[i + 1]); o.a = 0.22; o.s = 0.6; o.id = id + 1; return; }
        o.e = 0.02; o.a = 0.02; o.s = 0.6; o.id = id + 1; return;
      }
    }
    warp2(x * 0.4, z * 0.4);
    o.e = base * (0.88 + 0.22 * W2[0] + 0.07 * W2[1]); o.a = 0.2; o.s = 0.93; o.id = id;
  }
  const FLUID = (o, z, t) => { o.e = 0.018 + 0.025 * G(Math.sin(z * 4 + t * 0.5), 0.25); o.a = 0.012; o.s = 0.8; o.id = 7; };

  /* ═══════════════════════ SCENES ═══════════════════════ */
  // st (engine state): t, dt, rr, hr, rhythm, arrest, shift (cm, in-plane probe offset), vis (0..1 target in plane)
  const T0 = new Float32Array(2);

  // ── right / left upper quadrant (coronal, marker to the head = image left) ──
  function sceneUQ(P, left) {
    const pre = { br: 0, sh: 0, vis: 1, kv: 1, t: 0 };
    const K = left
      ? { dcx: 5.8, dcz: 8.0, R: 8.6, kx: 3.1, kz: 11.2, krx: 3.9, krz: 1.95, ka: -0.12, rib: [-4.8, 5.3], fat: 0.7 }
      : { dcx: 6.7, dcz: 9.3, R: 9.7, kx: 3.7, kz: 10.4, krx: 4.4, krz: 2.15, ka: -0.2, rib: [-5.2, 5.6], fat: 0.85 };
    const SPL = { cx: 0.8, cz: 5.6, rx: 4.6, rz: 2.8, a: 0.3 };
    const kcs = Math.cos(K.ka), ksn = Math.sin(K.ka), scs = Math.cos(SPL.a), ssn = Math.sin(SPL.a);
    const VES = left ? [-0.9, 5.2, 0.26, 1.2, 1.9, 6.4, 0.18, 1.0]
      : [-0.9, 5.4, 0.42, 1.15, 1.6, 7.5, 0.28, 1.6, -2.5, 8.7, 0.22, 1.0, 2.9, 4.5, 0.19, 2.8];
    const free = (P.free || 0) / 10, pleural = (P.pleural || 0) / 10;
    const spine = (x, z, o, at) => {
      if (z < at) return false;
      if (z < at + 0.32) { o.e = 2.1 * spec(x, z, 0, -1); o.a = 9; o.s = 0.3; o.id = 12; return true; }
      shadowBone(o); return true;
    };
    return {
      prep(st) {
        pre.br = Math.sin(st.t * TAU * clamp(st.rr || 14, 4, 40) / 60) * 0.75;
        pre.sh = st.shift || 0; pre.vis = st.vis === undefined ? 1 : st.vis;
        pre.kv = 0.5 + 0.5 * pre.vis; pre.t = st.t;
      },
      echo(x, z, o) {
        const xs = x + pre.sh;
        if (z > 0.9 && z < 2.9 && (bone(xs, z, o, K.rib[0], 1.95, 0.58) || bone(xs, z, o, K.rib[1], 2.0, 0.58))) return;
        if (wall(x, z, o, K.fat, 1.05)) return;
        const X = xs - pre.br, kv = pre.kv;
        warp2(X * 0.3, z * 0.3);
        const wx = X + 0.3 * W2[0], wz = z + 0.3 * W2[1];
        const ddx = wx - K.dcx, ddz = wz - K.dcz, dr = Math.hypot(ddx, ddz), dd = dr - K.R;
        const pf = pleural > 0 ? pleural * (0.28 + 0.72 * smooth(2.5, 12, z)) : 0;
        if (Math.abs(dd) < 0.17) { o.e = (0.3 + 1.9 * pre.vis) * spec(x, z, ddx, ddz); o.a = 0.5; o.s = 0.35; o.id = 6; return; }
        if (dd > 0) {
          if (pf > 0 && dd < pf) {
            // compressed lung tip waving in the effusion
            const ly = K.dcz - 1.5 + 0.5 * Math.sin(pre.t * 1.4);
            const tip = G(wz - ly, 0.55 + 0.2 * (dd / pf)) * smooth(pf * 0.45, pf * 0.75, dd);
            if (tip > 0.5) { o.e = 0.75; o.a = 0.5; o.s = 0.9; o.id = 8; return; }
            FLUID(o, z, pre.t); return;
          }
          if (pf > 0) {
            if (spine(x, z, o, 13.7)) return;                                                      // spine sign
            o.e = 0.5 + 0.12 * snoise(X, z); o.a = 0.34; o.s = 0.9; o.id = 8; return;              // airless lung
          }
          // aerated lung: mirror image of the organ across the diaphragm, no spine visible
          const m = (K.R * K.R) / (dr * dr);
          const mx = K.dcx + ddx * m, mz = K.dcz + ddz * m;
          o.e = (0.32 * pre.vis + 0.05) * (1 - 0.55 * smooth(0, 6, dd)); o.a = 0.45; o.s = 0.95; o.id = 19;
          o.du = mx - X; o.dv = mz - z; return;
        }
        // kidney: bean with a hilum notch on the deep side
        ellUV(wx, wz, K.kx, K.kz, kcs, ksn, T0);
        const ku = T0[0] / (K.krx * kv), kw = T0[1] / (K.krz * kv);
        const kn = Math.hypot(ku, kw) + (kw > 0 ? 0.18 * Math.exp(-ku * ku * 4) : 0);
        if (free > 0 && kn > 1.0 && kw < 0.35) {
          const th = free * (0.45 + 0.55 * smooth(-1.1, 1.2, ku)) * (0.85 + 0.25 * snoise(ku * 2, 5));
          if (kn < 1.0 + th / (K.krz * kv)) { FLUID(o, z, pre.t); return; }
        }
        if (kn < 1.0) {
          if (kn > 0.93) {
            const gu = T0[0] / (K.krx * K.krx), gv = T0[1] / (K.krz * K.krz);
            o.e = 1.5 * spec(x, z, gu * kcs - gv * ksn, gu * ksn + gv * kcs) + 0.2; o.a = 0.3; o.s = 0.45; o.id = 13; return;
          }
          const sinus = 0.47 + 0.1 * snoise(ku * 3, kw * 3);
          if (kn < sinus) {
            const cal = smooth(0.12, 0.42, Math.abs(snoise(ku * 5 + 3, kw * 5)));
            o.e = 0.45 + 0.65 * cal; o.a = 0.3; o.s = 0.95; o.id = 15; return;
          }
          const ang = Math.atan2(kw, ku);
          const pyr = G(Math.sin(ang * 4.5 + 0.6), 0.55) * smooth(sinus, sinus + 0.1, kn) * (1 - smooth(0.76, 0.88, kn));
          o.e = 0.33 - 0.2 * pyr; o.a = 0.18; o.s = 0.88; o.id = 14; return;
        }
        if (left) {
          const sn = ellN(wx, wz, SPL.cx, SPL.cz, SPL.rx * kv, SPL.rz * kv, scs, ssn);
          // subphrenic fluid (between diaphragm and spleen) and splenorenal recess
          if (free > 0 && dd > -free * 1.1 && sn < 1.3) { FLUID(o, z, pre.t); return; }
          if (sn < 1.0) {
            if (sn > 0.95) { o.e = 0.95; o.a = 0.25; o.s = 0.5; o.id = 16; return; }
            parenchyma(X, z, o, 0.6, VES, 17); return;
          }
          if (free > 0 && sn < 1.0 + free / 2.0 && kn < 1.0 + free / 1.6 + 0.3) { FLUID(o, z, pre.t); return; }
          if (z < 6.4 && X > 4.6 && gasLoop(X, z, o, 6.8, 4.5, 1.1, pre.t)) return;
          if (spine(x, z, o, 14.0)) return;
          o.e = 0.36 + 0.14 * snoise(X * 0.8, z * 0.8); o.a = 0.24; o.s = 0.9; o.id = 18; return;
        }
        // liver: fills the space under the diaphragm, its tip ends caudally (image right)
        const tipX = 7.8 - 0.5 * Math.max(0, z - 2.8) + 0.35 * snoise(z * 0.6, 2);
        if (X < tipX && z < 12.9) {
          parenchyma(X, z, o, 0.55, VES, 19);
          if (X > tipX - 0.15) { o.e = 1.0; o.s = 0.5; }
          return;
        }
        if (free > 0 && X < tipX + free * 0.85 && z > 3.4 && z < 10.5) { FLUID(o, z, pre.t); return; }
        if (X >= tipX && z < 9.5 && gasLoop(X, z, o, 9.4, 5.3, 1.5, pre.t)) return;
        if (spine(x, z, o, 14.3)) return;
        const ps = 0.5 + 0.5 * Math.sin((z - 13) * 16 + X * 0.6);
        o.e = 0.3 + 0.2 * ps * ps * ps; o.a = 0.25; o.s = 0.85; o.id = 18;
      },
      labels() {
        const L = [];
        const ix = X => X + pre.br - pre.sh;
        if (left) L.push({ k: 'spleen', x: ix(SPL.cx), z: SPL.cz });
        else L.push({ k: 'liver', x: ix(0.4), z: 6.0 });
        L.push({ k: 'kidney', x: ix(K.kx + 0.4), z: K.kz });
        L.push({ k: 'diaphragm', x: ix(K.dcx - K.R) + 0.8, z: K.dcz - 3.4, small: true });
        if (pleural > 0) L.push({ k: 'pleural', x: ix(K.dcx - K.R - pleural * 0.5) - 0.4, z: K.dcz + 2.4, tone: 'red' });
        if (pleural > 0) L.push({ k: 'spine', x: ix(K.dcx - K.R - pleural) - 0.8, z: 13.2, small: true });
        if (free > 0) L.push({ k: left ? 'free_luq' : 'free_ruq', x: ix(K.kx - 0.6), z: K.kz - K.krz - free * 0.5 - 0.5, tone: 'red' });
        return L;
      },
    };
  }

  // ── pelvis (transverse, marker to the patient's right = image left) ──
  function scenePelvis(P, seed) {
    const r = rng(seed + 3);
    const fill = 0.78 + r() * 0.3;
    const female = P.sex === 'f';
    const pre = { sh: 0, vis: 1, t: 0 };
    const free = (P.free || 0) / 10;
    const PW = 2.6;
    return {
      prep(st) { pre.sh = st.shift || 0; pre.vis = st.vis === undefined ? 1 : st.vis; pre.t = st.t; },
      echo(x, z, o) {
        if (wall(x, z, o, 1.1, 1.05)) return;
        const X = x + pre.sh;
        const v = 0.55 + 0.45 * pre.vis;
        const rx = 4.4 * fill * v, rz = 3.0 * fill * v, cz = 6.3 + 0.4 * (1 - fill);
        warp2(X * 0.4, z * 0.4);
        const wx = X + 0.18 * W2[0], wz = z + 0.18 * W2[1];
        const px = wx / rx, pz = (wz - cz) / rz;
        const ax = Math.abs(px), az = Math.abs(pz);
        const nb = Math.pow(Math.pow(ax, PW) + Math.pow(az, PW), 1 / PW);
        if (nb < 1.0) {
          if (nb > 0.93) {
            const nx = Math.sign(px) * Math.pow(ax, PW - 1) / rx, nz = Math.sign(pz) * Math.pow(az, PW - 1) / rz;
            o.e = 0.25 + 1.3 * spec(x, z, nx, nz); o.a = 0.25; o.s = 0.5; o.id = 20; return;
          }
          o.e = 0.01; o.a = 0.003; o.s = 0.5; o.id = 21; return;
        }
        const bot = cz + rz;
        if (free > 0) {
          // fluid hugs the back and sides of the bladder and pools in the pouch behind it (angular margins)
          const phi = Math.atan2(pz, px);
          const post = smooth(-0.05, 0.85, Math.sin(phi));
          const th = free * post * (0.8 + 0.35 * snoise(phi * 1.5, 3));
          if (nb < 1.0 + th / rz) { FLUID(o, z, pre.t); return; }
          const dz = z - bot;
          if (dz > -0.3 && dz < free * 1.6 && Math.abs(X) < free * 1.7 * (1 - dz / (free * 1.6))) { FLUID(o, z, pre.t); return; }
        }
        const un = female ? ellN(wx, wz, 0.2, bot + 2.5, 3.1, 1.8, 0.99, 0.12) : ellN(wx, wz, 0.0, bot + 1.8, 2.1, 1.35, 1, 0);
        if (un < 1.0) { o.e = un > 0.95 ? 0.62 : (female ? 0.48 : 0.4) + 0.1 * snoise(X, z); o.a = 0.24; o.s = 0.9; o.id = 22; return; }
        if (gasLoop(X, z, o, 0.3, bot + (female ? 5.6 : 4.6), 0.65, pre.t)) return;
        if (z < cz && Math.abs(X) > rx + 0.6 && gasLoop(X, z, o, Math.sign(X) * 6.8, 3.9, 1.0, pre.t)) return;
        const side = smooth(rx + 1.2, rx + 3.5, Math.abs(X)) * smooth(cz - 1, cz + 2, z);
        o.e = 0.36 + 0.14 * snoise(X * 0.7, z * 0.7) - 0.12 * side; o.a = 0.22; o.s = 0.9; o.id = 23;
      },
      labels() {
        const rz = 3.0 * fill, cz = 6.3 + 0.4 * (1 - fill);
        const L = [{ k: 'bladder', x: -pre.sh, z: cz }];
        L.push({ k: female ? 'uterus' : 'prostate', x: -pre.sh + (female ? 3.8 : 3.0), z: cz + rz + (female ? 2.6 : 1.9), small: true });
        if (free > 0) L.push({ k: 'free_pelvis', x: -pre.sh - 3.4, z: cz + rz + free * 0.6 + 0.6, tone: 'red' });
        return L;
      },
    };
  }

  // ── heart, subxiphoid (liver window near field, RV on top, apex to the image right) ──
  function sceneCardiac(P, seed) {
    const pre = { sh: 0, vis: 1, t: 0, ph: 0, sys: 0, atr: 0, open: 0, cx: 1.0, cz: 10.3, rvc: 1, quiver: 0, eff: 0 };
    const eff0 = (P.effusion || 0) / 10;
    const HA = -0.16, hcs = Math.cos(HA), hsn = Math.sin(HA);
    const H = { rx: 5.0, rz: 3.4 };
    const UV = new Float32Array(2);
    const leaflet = (u, v, u0, v0, len, open, ang) => {
      const a = ang + open * 1.05;
      const du = Math.cos(a), dv = Math.sin(a);
      const pu = u - u0, pv = v - v0;
      const along = pu * du + pv * dv;
      if (along < 0 || along > len) return false;
      const bend = 0.18 * Math.sin(Math.PI * along / len) * (open ? 1 : 0.3);
      return Math.abs(-pu * dv + pv * du - bend) < 0.055;
    };
    function geom(X, z) {
      ellUV(X, z, pre.cx, pre.cz, hcs, hsn, UV);
      const u = UV[0], v = UV[1];
      const s = 1 - 0.07 * pre.sys, vis = 0.55 + 0.45 * pre.vis;
      const wob = 0.035 * snoise(u * 1.2, v * 1.2);
      const hn = Math.hypot(u / (H.rx * s * vis), v / (H.rz * s * vis)) + wob;
      const effLocal = pre.eff * (0.7 + 0.45 * smooth(-3, 3, v)) + 0.08;
      const pn = Math.hypot(u / (H.rx * s * vis + effLocal), v / (H.rz * s * vis + effLocal)) + wob * 0.6;
      return [u, v, hn, pn];
    }
    return {
      eff: eff0,
      prep(st) {
        pre.sh = st.shift || 0; pre.vis = st.vis === undefined ? 1 : st.vis; pre.t = st.t;
        const arrest = st.arrest === true || st.rhythm === 'asystole' || (st.rhythm === 'pea' && (st.hr || 0) < 25);
        const vf = st.rhythm === 'vf' || st.rhythm === 'vt';
        const hr = clamp(st.hr || 80, 20, 220);
        if (!arrest && !vf) pre.ph = (pre.ph + (st.dt || 0.033) * hr / 60) % 1;
        const ph = pre.ph;
        pre.sys = arrest || vf ? 0 : (ph < 0.36 ? Math.sin(Math.PI * ph / 0.36) : 0);
        pre.atr = arrest || vf ? 0 : (ph > 0.82 && ph < 0.97 ? Math.sin(Math.PI * (ph - 0.82) / 0.15) : 0);
        pre.open = arrest || vf ? 0 : (ph > 0.42 && ph < 0.92 ? 1 : 0);
        pre.quiver = vf ? 1 : 0;
        pre.eff = st.effusion !== undefined && st.effusion !== null ? st.effusion / 10 : eff0;
        const beat = Math.floor((st.t || 0) * hr / 60);
        const swing = pre.eff > 1.3 && !arrest ? (beat % 2 ? 1 : -1) * Math.min(0.9, (pre.eff - 1.3) * 0.7) * Math.sin(Math.PI * ph) : 0;
        pre.cx = 1.0 + swing * 0.6; pre.cz = 10.3 + pre.eff * 0.35 + swing * 0.25;
        pre.rvc = P.collapse && !arrest && pre.eff > 0.6 ? 1 - 0.75 * (ph > 0.4 && ph < 0.85 ? Math.sin(Math.PI * (ph - 0.4) / 0.45) : 0) : 1;
      },
      echo(x, z, o) {
        if (wall(x, z, o, 0.9, 0.9)) return;
        const X = x + pre.sh;
        const liverEdge = 6.4 - 0.46 * (X + 6.5) + 0.5 * Math.sin(X * 0.4 + 1) + 0.15 * snoise(X * 0.5, 1);
        if (z < liverEdge && X < 4.4) {
          if (z > liverEdge - 0.15) { o.e = 0.35 + 0.9 * spec(x, z, 0.46, 1); o.a = 0.25; o.s = 0.4; o.id = 6; return; }
          parenchyma(X, z, o, 0.55, [-3.7, 3.9, 0.36, 1.0, -1.4, 3.1, 0.22, 1.4], 19); return;
        }
        const g = geom(X, z);
        const u = g[0], v = g[1], hn = g[2], pn = g[3];
        if (pn >= 1.0 && pn < 1.0 + 0.2 / H.rz) {
          ellUV(X, z, pre.cx, pre.cz, hcs, hsn, UV);
          o.e = 0.3 + 1.6 * spec(x, z, UV[0] * hcs - UV[1] * hsn, UV[0] * hsn + UV[1] * hcs); o.a = 0.35; o.s = 0.35; o.id = 24; return;
        }
        if (hn >= 1.0 && pn < 1.0) {
          if (pre.eff > 0.05) { FLUID(o, z, pre.t); o.e += 0.05 * Math.max(0, snoise(u * 1.5 + pre.t * 0.2, v * 1.5)); return; }
          o.e = 1.1; o.a = 0.3; o.s = 0.4; o.id = 24; return;
        }
        if (hn < 1.0) {
          const q = pre.quiver ? 0.07 * Math.sin(pre.t * 31 + X * 3) : 0;
          const tb = 0.07 * snoise(u * 4, v * 4);                      // trabeculae roughen the endocardium
          const k = 1 - 0.2 * pre.sys, ka = 1 + 0.12 * pre.sys - 0.15 * pre.atr;
          // LV: bullet-shaped cavity tapering to the apex (image right), thick wall + septum around it
          const lu = (u - 1.15) / (3.0 * k);
          const lvW = 1.2 * k * (1 - 0.4 * clamp(lu, -1, 1));
          const lvN = Math.hypot(lu, (v - 0.85) / lvW);
          const lvOut = Math.hypot((u - 1.15) / (3.0 * k + 0.85), (v - 0.85) / (lvW + 0.95));
          // RV: crescent wrapped over the front of the LV; in tamponade its free wall caves in during diastole
          const rvTop = 0.35 + 1.05 * k * pre.rvc;
          const rvN = Math.hypot((u - 0.55) / (3.5 * k), (v + 0.15 + (1 - pre.rvc) * 0.3) / (rvTop + 0.55));
          const inLV = lvN + tb < 1 + q;
          const inRV = rvN + tb * 0.6 < 1 + q && lvOut > 1.0;
          const inRA = Math.hypot((u + 2.9) / (1.45 * ka), (v + 1.0) / (1.2 * ka)) + tb * 0.5 < 1;
          const inLA = Math.hypot((u + 2.75) / (1.4 * ka), (v - 1.45) / (1.1 * ka)) + tb * 0.5 < 1;
          if (inRV || inLV || inRA || inLA) {
            if (leaflet(u, v, -1.75, 0.3, 1.25, pre.open, 0.35) || leaflet(u, v, -1.75, 1.5, 1.1, pre.open, -0.35)
              || leaflet(u, v, -1.85, -1.75, 1.1, pre.open, 0.3) || leaflet(u, v, -1.85, -0.55, 1.0, pre.open, -0.3)) {
              o.e = 0.95; o.a = 0.2; o.s = 0.55; o.id = 25; return;
            }
            o.e = 0.025 + 0.04 * Math.max(0, snoise(u * 1.4 + pre.t * 0.9, v * 1.4)); o.a = 0.03; o.s = 0.9; o.id = 26; return;
          }
          o.e = 0.42 + 0.14 * pre.sys + 0.1 * snoise(u * 2.2, v * 2.2); o.a = 0.28; o.s = 0.86; o.id = 27;
          o.du = u * 0.5 * pre.sys; o.dv = v * 0.35 * pre.sys;
          return;
        }
        const an = Math.hypot((X + 0.8) / 0.8, (z - 15.8) / 0.8);
        if (an < 1.15) { o.e = an > 0.9 ? 0.25 + 0.9 * spec(x, z, X + 0.8, z - 15.8) : 0.02; o.a = 0.05; o.s = 0.5; o.id = 28; return; }
        if (z > 17.2) { if (z < 17.5) { o.e = 1.9 * spec(x, z, 0, -1); o.a = 9; o.s = 0.3; o.id = 12; return; } shadowBone(o); return; }
        o.e = 0.3 + 0.12 * snoise(X * 0.8, z * 0.8); o.a = 0.24; o.s = 0.9; o.id = 18;
      },
      // what the needle tip sits in: 'liver' | 'tissue' | 'sac' | 'heart'
      region(x, z) {
        const X = x + pre.sh;
        const liverEdge = 6.4 - 0.46 * (X + 6.5) + 0.5 * Math.sin(X * 0.4 + 1);
        if (z < liverEdge && X < 4.4) return 'liver';
        const g = geom(X, z);
        if (g[2] < 1.0) return 'heart';
        if (g[3] < 1.0) return pre.eff > 0.05 ? 'sac' : 'heart';
        return 'tissue';
      },
      labels() {
        const L = [];
        const toImg = (u, v) => [pre.cx + u * hcs - v * hsn - pre.sh, pre.cz + u * hsn + v * hcs];
        L.push({ k: 'liver', x: -4.4 - pre.sh, z: 3.4 });
        let p = toImg(1.4, -1.2); L.push({ k: 'rv', x: p[0], z: p[1], small: true });
        p = toImg(1.6, 0.85); L.push({ k: 'lv', x: p[0], z: p[1], small: true });
        p = toImg(-2.9, -1.0); L.push({ k: 'ra', x: p[0], z: p[1], small: true });
        p = toImg(-2.75, 1.45); L.push({ k: 'la', x: p[0], z: p[1], small: true });
        if (pre.eff > 0.05) { p = toImg(2.4, H.rz + pre.eff * 0.85 + 0.15); L.push({ k: 'effusion', x: p[0], z: p[1] + 0.2, tone: 'red' }); }
        return L;
      },
    };
  }

  // ── lung, anterior (longitudinal across two ribs) ──
  function sceneLung(P, seed) {
    const r = rng(seed + 29);
    const slide = !P.ptx;
    const pre = { sh: 0, vis: 1, t: 0, off: 0, jit: 0 };
    const bl = [];
    for (let i = 0; i < (P.b || 0); i++) bl.push(-1.4 + r() * 2.8);
    const zP = 2.12, RX = 2.05;
    return {
      prep(st) {
        pre.sh = st.shift || 0; pre.vis = st.vis === undefined ? 1 : st.vis; pre.t = st.t;
        const rr = clamp(st.rr || 14, 4, 40);
        pre.off = slide ? Math.sin(st.t * TAU * rr / 60) * 0.5 : 0;
        // sliding decorrelates the speckle under the pleura frame to frame (the "sand" in M-mode)
        pre.jit = slide ? (pre.jit + 3.71) % 97 : 0;
      },
      echo(x, z, o) {
        const X = x + pre.sh * 1.4;
        if (z > 1.0 && z < 2.6 && (bone(X, z, o, -RX, 1.72, 0.5) || bone(X, z, o, RX, 1.72, 0.5))) return;
        if (wall(x, z, o, 0.45, 0.82)) return;
        const dp = z - zP - 0.04 * Math.sin(X * 1.3);
        if (Math.abs(dp) < 0.075) {
          o.e = 2.3 * (0.85 + 0.15 * Math.sin(X * 5 + pre.off * 9)); o.a = 1.1; o.s = 0.55; o.id = 30;
          if (slide) o.du = pre.off * 3 + pre.jit;
          return;
        }
        if (dp < 0) { o.e = 0.4 + 0.08 * snoise(X, z * 2); o.a = 0.24; o.s = 0.82; o.id = 31; return; }
        let e = 0.06;
        for (let k = 2; k <= 6; k++) e += (P.ptx ? 1.2 : 0.95) * Math.pow(0.6, k - 1) * G(z - zP * k, 0.075);
        for (let i = 0; i < bl.length; i++) e += 1.1 * G(X - bl[i] - pre.off * 0.6, 0.1);
        o.e = e; o.a = 0.08; o.s = 0.9; o.id = 32;
        if (slide) { o.du = pre.off * 4 + pre.jit; o.dv = pre.jit * 0.37; }
      },
      labels() {
        return [
          { k: 'rib', x: -RX - pre.sh * 1.4, z: 0.9, small: true },
          { k: 'rib', x: RX - pre.sh * 1.4, z: 0.9, small: true },
          { k: 'pleura', x: 0.0 - pre.sh * 1.4, z: zP - 0.42, small: true },
        ];
      },
      pleuraDepth: zP,
    };
  }

  // ── no window: abdominal wall, mesenteric fat and bowel gas ──
  function sceneBowel(P, seed) {
    const pre = { t: 0, sh: 0 };
    const r = rng(seed + 47);
    const loops = [];
    for (let i = 0; i < 6; i++) loops.push([-7 + r() * 14, 3.6 + r() * 6, 0.7 + r() * 0.8]);
    return {
      prep(st) { pre.t = st.t; pre.sh = (st.shift || 0) + (st.wander || 0); },
      echo(x, z, o) {
        if (wall(x, z, o, 1.0, 1.0)) return;
        const X = x + pre.sh;
        for (let i = 0; i < loops.length; i++) {
          const l = loops[i];
          if (gasLoop(X, z, o, l[0] + Math.sin(pre.t * 0.7 + i) * 0.3, l[1], l[2], pre.t)) return;
        }
        o.e = 0.4 + 0.2 * snoise(X * 0.7, z * 0.7); o.a = 0.26; o.s = 0.9; o.id = 40;
      },
      labels() { return []; },
    };
  }

  // ── probe in the air: lens reverberation only ──
  function sceneAir() {
    return {
      prep() {},
      echo(x, z, o) {
        o.e = z < 0 ? 0 : 0.9 * Math.pow(0.55, Math.floor(z / 0.32)) * G(((z % 0.32) - 0.05), 0.04) + 0.008;
        o.a = 0; o.s = 0.3; o.id = 41;
      },
      labels() { return []; },
    };
  }

  function scene(win, P, seed) {
    P = P || {};
    seed = seed >>> 0;
    switch (win) {
      case 'ruq': return sceneUQ(P, false);
      case 'luq': return sceneUQ(P, true);
      case 'pelvis': return scenePelvis(P, seed);
      case 'cardiac': return sceneCardiac(P, seed);
      case 'lung_r': case 'lung_l': return sceneLung(P, seed + (win === 'lung_l' ? 7 : 0));
      case 'air': return sceneAir();
      default: return sceneBowel(P, seed);
    }
  }

  /* ═══════════════════════ ENGINE ═══════════════════════ */
  function BMode(canvas, opts = {}) {
    const NL = opts.lines || 136, NS = opts.samples || 240;
    const R0 = 2.6, HALF = 35 * Math.PI / 180;
    const seed = (opts.seed || 7) >>> 0;
    const S1 = speckle(seed), S2 = speckle((seed * 31 + 5) >>> 0);
    const raw = new Float32Array(NL * NS), disp = new Float32Array(NL * NS);
    const st = {
      depth: 16, gain: 55, focus: 8, t: 0, dt: 0.033, frozen: false, contact: true, q: 1, shift: 0, vis: 1,
      scene: null, rr: 14, hr: 80, rhythm: 'sinus', needle: null, persist: 0.38, haze: 0, wander: 0,
    };
    const o = { e: 0, a: 0, s: 0, id: 0, du: 0, dv: 0 };
    const ctx = canvas.getContext('2d');
    let W = 0, H = 0, img = null, lutL = null, lutS = null, geoKey = '', k = 1, x0 = 0, y0 = 0, zTop = 0;
    let first = true;

    function geometry() {
      const w = canvas.width, h = canvas.height, D = st.depth;
      const key = `${w}x${h}:${D}`;
      if (key === geoKey) return;
      geoKey = key; W = w; H = h;
      zTop = R0 * Math.cos(HALF) - R0;
      const hcm = D - zTop + 0.25, wcm = 2 * (R0 + D) * Math.sin(HALF) + 0.4;
      k = Math.min(H / hcm, W / wcm);
      x0 = W / 2; y0 = (H - hcm * k) / 2 - zTop * k + 0.12 * k;
      img = ctx.createImageData(W, H);
      lutL = new Float32Array(W * H); lutS = new Float32Array(W * H);
      for (let py = 0, i = 0; py < H; py++) {
        for (let px = 0; px < W; px++, i++) {
          const x = (px - x0) / k, z = (py - y0) / k;
          const r = Math.hypot(x, z + R0), th = Math.atan2(x, z + R0);
          if (Math.abs(th) > HALF || r < R0 || r > R0 + D) { lutL[i] = -1; continue; }
          lutL[i] = (th + HALF) / (2 * HALF) * (NL - 1);
          lutS[i] = (r - R0) / D * (NS - 1);
        }
      }
      first = true;
    }

    function needleEcho(x, z) {
      const n = st.needle;
      if (!n || !n.on) return 0;
      const dx = Math.sin(n.ang), dz = Math.cos(n.ang);
      const px = x - n.ex, pz = z - n.ez;
      const along = px * dx + pz * dz;
      if (along < 0 || along > n.depth + 0.05) return 0;
      const across = Math.abs(-px * dz + pz * dx);
      const vis = clamp(n.inPlane === undefined ? 1 : n.inPlane, 0, 1);
      let e = 0;
      if (across < 0.07) e = 2.8 * vis * (0.6 + 0.4 * Math.sin(along * 9) * Math.sin(along * 9));   // shaft (dotted: out of plane)
      if (along > n.depth - 0.25 && across < 0.14) e = Math.max(e, 3.2 * Math.max(vis, 0.45));       // bevel tip
      // reverberation tail just behind the shaft
      if (e === 0 && across < 0.4 && (-px * dz + pz * dx) > 0) e = 0.55 * vis * G(across, 0.18) * (0.5 + 0.5 * Math.sin(across * 40));
      return e;
    }

    // per-sample geometry, rebuilt when depth / focus change
    let gKey = '', GX = null, GZ = null, GF = null, GLAT = null, GTGC = null;
    function sampleGeometry() {
      const key = `${st.depth}:${st.focus}`;
      if (key === gKey) return;
      gKey = key;
      const n = NL * NS, D = st.depth, dz = D / NS, fw = 0.36 * D + 1.6;
      GX = new Float32Array(n); GZ = new Float32Array(n); GF = new Float32Array(n); GLAT = new Float32Array(n); GTGC = new Float32Array(n);
      for (let l = 0; l < NL; l++) {
        const th = -HALF + (2 * HALF) * l / (NL - 1);
        const sn = Math.sin(th), cs = Math.cos(th);
        const ap = 1 - 0.4 * Math.pow(Math.abs(th) / HALF, 5);
        for (let s = 0; s < NS; s++) {
          const i = l * NS + s, r = R0 + (s + 0.5) * dz;
          const x = r * sn, z = r * cs - R0;
          const f = Math.exp(-((z - st.focus) * (z - st.focus)) / (fw * fw));
          GX[i] = x; GZ[i] = z;
          GLAT[i] = 19 / (1 + (1 - f) * 0.85);
          GTGC[i] = Math.exp(0.2 * z) * (0.8 + 0.32 * f) * ap * (z < 0.35 ? 1 : 1);
          GF[i] = z < 0.35 ? 0.25 * G(z - 0.05, 0.08) : 0;
        }
      }
    }

    function compute() {
      sampleGeometry();
      const D = st.depth, sc = st.scene, dz = D / NS;
      if (sc && sc.prep) sc.prep(st);
      const q = clamp(st.q, 0, 1);
      const haze = (1 - q) * 0.9 + st.haze;
      const t = st.t;
      const hasNeedle = !!(st.needle && st.needle.on);
      const echo = sc ? sc.echo : null;
      for (let l = 0; l < NL; l++) {
        let T = 1;
        const base = l * NS;
        for (let s = 0; s < NS; s++) {
          const i = base + s;
          const x = GX[i], z = GZ[i];
          o.e = 0.3; o.a = 0.2; o.s = 0.85; o.id = 0; o.du = 0; o.dv = 0;
          if (echo) echo(x, z, o, st);
          let e = o.e, a = o.a;
          if (hasNeedle) { const ne = needleEcho(x, z); if (ne > e) e = ne; }
          if (haze > 0.02 && z > 1.6 && st.contact) {
            const hz = vnoise(x * 0.35 + t * 0.15, z * 0.35);
            e = lerp(e, 0.18 + 0.4 * hz, clamp(haze * (0.6 + 0.5 * hz), 0, 1));
            a += haze * 0.08;
          }
          const id = o.id, lat = GLAT[i];
          const spk = sp(id & 1 ? S2 : S1, (x + o.du) * lat + id * 37.13, (z + o.dv) * 30 + id * 19.7);
          raw[i] = e * (1 - o.s + o.s * spk) * T * GTGC[i] + GF[i];
          const ad = a * dz;
          T *= ad < 0.3 ? 1 - ad + ad * ad * 0.5 : Math.exp(-ad);
        }
      }
    }

    const tmp = new Float32Array(NL * NS);
    function compress() {
      const gdb = (st.gain - 50) * 0.42;
      const hi = 11 + gdb, lo = hi - 50;
      const p = first ? 0 : st.persist;
      // lateral beam width: a 3-tap blur across scan lines softens edges like a real aperture
      for (let l = 0; l < NL; l++) {
        const a = l > 0 ? l - 1 : l, b = l < NL - 1 ? l + 1 : l;
        for (let s = 0; s < NS; s++) tmp[l * NS + s] = 0.25 * raw[a * NS + s] + 0.5 * raw[l * NS + s] + 0.25 * raw[b * NS + s];
      }
      for (let i = 0; i < tmp.length; i++) {
        const db = 20 * Math.log10(tmp[i] + 1e-5);
        let d = (db - lo) / (hi - lo);
        d = d < 0 ? 0 : d > 1 ? 1 : d;
        d = d * d * (1.5 - 0.5 * d);
        disp[i] = p ? disp[i] * p + d * (1 - p) : d;
      }
      first = false;
    }

    function draw() {
      const data = img.data, N = W * H;
      for (let i = 0, p = 0; i < N; i++, p += 4) {
        const l = lutL[i];
        if (l < 0) { data[p + 3] = 0; continue; }
        const s = lutS[i];
        const l0 = l | 0, s0 = s | 0, fl = l - l0, fs = s - s0;
        const l1 = l0 + 1 < NL ? l0 + 1 : l0, s1 = s0 + 1 < NS ? s0 + 1 : s0;
        const a = disp[l0 * NS + s0], b = disp[l1 * NS + s0], c = disp[l0 * NS + s1], d = disp[l1 * NS + s1];
        const v = (a + (b - a) * fl + (c - a) * fs + (a - b - c + d) * fl * fs) * 255;
        data[p] = v * 0.97; data[p + 1] = v * 0.99; data[p + 2] = v; data[p + 3] = 255;
      }
      ctx.putImageData(img, 0, 0);
    }

    const api = {
      st, canvas, NL, NS,
      set(patch) {
        const reScene = patch.scene && patch.scene !== st.scene;
        Object.assign(st, patch);
        if (reScene) first = true;
        return api;
      },
      frame(dt = 0.033) {
        geometry();
        if (!st.frozen) {
          st.dt = dt; st.t += dt;
          if (!st.contact) st.scene = st.airScene || (st.airScene = sceneAir());
          compute(); compress();
        }
        draw();
        return api;
      },
      redraw() { geometry(); draw(); return api; },
      toPx(x, z) { geometry(); return [x0 + x * k, y0 + z * k]; },
      fromPx(px, py) {
        geometry();
        const x = (px - x0) / k, z = (py - y0) / k;
        const r = Math.hypot(x, z + R0), th = Math.atan2(x, z + R0);
        if (Math.abs(th) > HALF || r < R0 || r > R0 + st.depth) return null;
        return [x, z];
      },
      scale() { geometry(); return k; },
      sector() { geometry(); return { x0, y0, k, R0, HALF, D: st.depth, zTop }; },
      // centre scan line resampled to h values (M-mode column, 0..1)
      mline(h) {
        const out = new Float32Array(h), l = (NL / 2) | 0;
        for (let i = 0; i < h; i++) {
          const s = i / (h - 1) * (NS - 1), s0 = s | 0, f = s - s0, s1 = s0 + 1 < NS ? s0 + 1 : s0;
          out[i] = disp[l * NS + s0] * (1 - f) + disp[l * NS + s1] * f;
        }
        return out;
      },
      // walk the needle path: where the sac starts / the heart wall is, relative to the tip
      needlePath() {
        const n = st.needle, sc = st.scene;
        if (!n || !sc || !sc.region) return null;
        const dx = Math.sin(n.ang), dz = Math.cos(n.ang);
        let sac = null, wall = null, tipIn = null;
        for (let d = 0; d <= 16; d += 0.05) {
          const reg = sc.region(n.ex + dx * d, n.ez + dz * d);
          if (sac === null && reg === 'sac') sac = d;
          if (wall === null && reg === 'heart') { wall = d; break; }
        }
        tipIn = sc.region(n.ex + dx * n.depth, n.ez + dz * n.depth);
        return { sac, wall, tip: n.depth, hit: tipIn };
      },
    };
    return api;
  }

  window.NZUS = { BMode, scene, speckle, rng, clamp, lerp, smooth };
})();

/* ═══════════════════════════════════════════════════════════
   Part 2 · device face, orientation view, protocol map, treatment plan
   (NUI only — the cart DUI loads Part 1 alone)
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA || !window.NZA.app || !window.NZUS) return;
  const U = window.NZUS;
  const { clamp, lerp, smooth } = U;
  const esc = NZA.esc, icon = NZA.icon;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };
  const R = s => NZA.rich(s);

  /* ─────────── eFAST windows (torso space: x -1 = patient's right flank … +1 left flank,
                 y 0 = pubis … 1 = clavicles; metres per unit SX / SY) ─────────── */
  const SX = 0.17, SY = 0.55;
  const WINS = [
    { id: 'ruq', x: -1.0, y: 0.56, r0: 0.024, r1: 0.09, rot: 0, tilt: 0, depth: 16, focus: 9 },
    { id: 'luq', x: 1.0, y: 0.64, r0: 0.024, r1: 0.09, rot: 0, tilt: 0, depth: 16, focus: 8 },
    { id: 'pelvis', x: 0.0, y: 0.05, r0: 0.026, r1: 0.095, rot: 90, alt: 0, tilt: 0, depth: 14, focus: 7 },
    { id: 'cardiac', x: 0.08, y: 0.69, r0: 0.022, r1: 0.085, rot: 90, tilt: 20, depth: 18, focus: 10 },
    { id: 'lung_r', x: -0.45, y: 0.9, r0: 0.045, r1: 0.13, rot: 0, tilt: 0, depth: 8, focus: 3 },
    { id: 'lung_l', x: 0.45, y: 0.9, r0: 0.045, r1: 0.13, rot: 0, tilt: 0, depth: 8, focus: 3 },
  ];
  const WIN = {};
  WINS.forEach(w => { WIN[w.id] = w; });
  const WNAME = {
    ruq: ['w_ruq', 'Right upper quadrant'], luq: ['w_luq', 'Left upper quadrant'], pelvis: ['w_pelvis', 'Pelvis'],
    cardiac: ['w_cardiac', 'Heart · below the breastbone'], lung_r: ['w_lung_r', 'Right chest wall'], lung_l: ['w_lung_l', 'Left chest wall'],
  };
  const WSHORT = { ruq: ['s_ruq', 'RUQ'], luq: ['s_luq', 'LUQ'], pelvis: ['s_pelvis', 'PELV'], cardiac: ['s_cardiac', 'HEART'], lung_r: ['s_lung_r', 'LUNG R'], lung_l: ['s_lung_l', 'LUNG L'] };
  const wName = id => (WNAME[id] ? T(WNAME[id][0], WNAME[id][1]) : '');
  const wShort = id => (WSHORT[id] ? T(WSHORT[id][0], WSHORT[id][1]) : '');
  const angDiff = (a, b) => { let d = ((a - b) % 360 + 540) % 360 - 180; return d; };

  // what the probe sees from torso position (x, y) with rotation / tilt (deg)
  function probeView(x, y, rot, tilt) {
    let best = null, bd = 1e9;
    for (const w of WINS) {
      const dx = (x - w.x) * SX, dy = (y - w.y) * SY;
      const d = Math.hypot(dx, dy);
      if (d < bd) { bd = d; best = w; }
    }
    const w = best;
    const qPos = 1 - smooth(w.r0, w.r1, bd);
    let rerr = Math.abs(angDiff(rot, w.rot));
    if (rerr > 90) rerr = 180 - rerr;                                     // reversed marker still images (mirrored)
    if (w.alt !== undefined) { let r2 = Math.abs(angDiff(rot, w.alt)); if (r2 > 90) r2 = 180 - r2; rerr = Math.min(rerr, r2); }
    const qRot = 1 - smooth(18, 62, rerr) * 0.85;
    const terr = Math.abs((tilt || 0) - (w.tilt || 0));
    const qTilt = 1 - smooth(8, 26, terr) * 0.8;
    // offsets: in-plane (image shifts) and out-of-plane (targets fade)
    const r = rot * Math.PI / 180;
    const dirX = -Math.sin(r), dirY = Math.cos(r);
    const ox = (x - w.x) * SX, oy = (y - w.y) * SY;
    const inPlane = (ox * dirX / 1 + oy * dirY);
    const perp = (-ox * dirY + oy * dirX);
    const flip = Math.abs(angDiff(rot, w.alt !== undefined && Math.abs(angDiff(rot, w.alt)) < Math.abs(angDiff(rot, w.rot)) ? w.alt : w.rot)) > 90;
    return {
      win: w, dist: bd, qPos, qRot, qTilt, q: qPos * qRot * qTilt, rerr, terr,
      shift: -inPlane * 100 * (flip ? -1 : 1), vis: Math.exp(-Math.pow(perp * 100 / 2.4, 2)) * qRot, flip,
    };
  }

  // anchors grid (Lua streams g<i>_<j> for these torso coords) → inverse map a screen point to torso space
  const GX = [-1.15, -0.58, 0, 0.58, 1.15], GY = [-0.06, 0.26, 0.52, 0.78, 1.04];
  function invQuad(p, a, b, c, d) {
    // bilinear P(u,v) = a(1-u)(1-v) + b u (1-v) + c u v + d (1-u) v ; Newton solve
    let u = 0.5, v = 0.5;
    for (let it = 0; it < 8; it++) {
      const px = a.x * (1 - u) * (1 - v) + b.x * u * (1 - v) + c.x * u * v + d.x * (1 - u) * v;
      const py = a.y * (1 - u) * (1 - v) + b.y * u * (1 - v) + c.y * u * v + d.y * (1 - u) * v;
      const ex = px - p.x, ey = py - p.y;
      const dxu = (b.x - a.x) * (1 - v) + (c.x - d.x) * v, dyu = (b.y - a.y) * (1 - v) + (c.y - d.y) * v;
      const dxv = (d.x - a.x) * (1 - u) + (c.x - b.x) * u, dyv = (d.y - a.y) * (1 - u) + (c.y - b.y) * u;
      const det = dxu * dyv - dxv * dyu;
      if (Math.abs(det) < 1e-9) break;
      u -= (ex * dyv - ey * dxv) / det; v -= (ey * dxu - ex * dyu) / det;
    }
    return [u, v];
  }
  function screenToTorso(p, anchors) {
    if (!anchors) return null;
    let best = null;
    for (let j = 0; j < GY.length - 1; j++) {
      for (let i = 0; i < GX.length - 1; i++) {
        const a = anchors[`g${i}_${j}`], b = anchors[`g${i + 1}_${j}`], c = anchors[`g${i + 1}_${j + 1}`], d = anchors[`g${i}_${j + 1}`];
        if (!a || !b || !c || !d || a.visible === false || b.visible === false || c.visible === false || d.visible === false) continue;
        const [u, v] = invQuad(p, a, b, c, d);
        const out = Math.max(0, -u, u - 1) + Math.max(0, -v, v - 1);
        if (!best || out < best.out) best = { out, x: lerp(GX[i], GX[i + 1], u), y: lerp(GY[j], GY[j + 1], v) };
      }
    }
    if (!best) return null;
    return { x: best.x, y: best.y, inside: best.out < 0.02 };
  }
  function torsoToScreen(x, y, anchors) {
    if (!anchors) return null;
    const i = clamp(Math.floor((x - GX[0]) / (GX[1] - GX[0])), 0, GX.length - 2);
    const j = clamp(Math.floor((y - GY[0]) / (GY[1] - GY[0])), 0, GY.length - 2);
    const a = anchors[`g${i}_${j}`], b = anchors[`g${i + 1}_${j}`], c = anchors[`g${i + 1}_${j + 1}`], d = anchors[`g${i}_${j + 1}`];
    if (!a || !b || !c || !d) return null;
    const u = (x - GX[i]) / (GX[i + 1] - GX[i]), v = (y - GY[j]) / (GY[j + 1] - GY[j]);
    return {
      x: a.x * (1 - u) * (1 - v) + b.x * u * (1 - v) + c.x * u * v + d.x * (1 - u) * v,
      y: a.y * (1 - u) * (1 - v) + b.y * u * (1 - v) + c.y * u * v + d.y * (1 - u) * v,
      visible: a.visible !== false && c.visible !== false,
    };
  }

  /* ─────────── 3D orientation view (three.js): torso, probe, beam plane ─────────── */
  function Orient(canvas) {
    const THREE = window.THREE;
    if (!THREE) return null;
    let renderer;
    try { renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: false }); } catch (e) { return null; }
    renderer.setPixelRatio(1);
    const scene = new THREE.Scene();
    const cam = new THREE.PerspectiveCamera(30, canvas.width / canvas.height, 0.05, 20);
    cam.position.set(0.78, 0.82, -0.98); cam.lookAt(0, -0.02, 0.03);
    scene.add(new THREE.HemisphereLight(0xcfe9e6, 0x101416, 0.9));
    const dl = new THREE.DirectionalLight(0xffffff, 0.8); dl.position.set(1, 2, -1); scene.add(dl);
    // torso: a lathed body of revolution squashed front-to-back, lying along +Z (head) with the front up (+Y)
    const prof = [];
    const pts = [[0.0, -0.32], [0.15, -0.31], [0.19, -0.24], [0.17, -0.1], [0.155, 0.02], [0.17, 0.14], [0.2, 0.25], [0.205, 0.3], [0.13, 0.34], [0.0, 0.345]];
    pts.forEach(p => prof.push(new THREE.Vector2(p[0], p[1])));
    const lg = new THREE.LatheGeometry(prof, 40);
    lg.rotateX(Math.PI / 2);
    lg.scale(1, 0.58, 1);
    const skin = new THREE.Mesh(lg, new THREE.MeshStandardMaterial({ color: 0x2b4a49, roughness: 0.55, metalness: 0.15, transparent: true, opacity: 0.94, emissive: 0x06201e }));
    scene.add(skin);
    const wire = new THREE.LineSegments(new THREE.WireframeGeometry(lg), new THREE.LineBasicMaterial({ color: 0x0fd4c4, transparent: true, opacity: 0.24 }));
    scene.add(wire);
    // ribs hint
    for (let i = 0; i < 6; i++) {
      const z = 0.05 + i * 0.045;
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.19, 0.0035, 6, 40, Math.PI), new THREE.MeshBasicMaterial({ color: 0x0fd4c4, transparent: true, opacity: 0.12 }));
      ring.scale.set(1, 0.6, 1); ring.position.set(0, 0, z); scene.add(ring);
    }
    // window dots
    const dots = {};
    const surf = (x, y) => {
      // torso coords → a point on the front / side surface + its normal
      const z = lerp(-0.3, 0.3, y);
      const a = clamp(x, -1.2, 1.2) * 1.2;                         // radians around the body axis from the front
      const rx = 0.19, ry = 0.11;
      const p = new THREE.Vector3(-Math.sin(a) * rx, Math.cos(a) * ry, z);
      const n = new THREE.Vector3(-Math.sin(a) / rx, Math.cos(a) / ry, 0).normalize();
      return { p, n };
    };
    WINS.forEach(w => {
      const s = surf(w.x, w.y);
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.014, 12, 10), new THREE.MeshBasicMaterial({ color: 0xffffff }));
      m.position.copy(s.p).addScaledVector(s.n, 0.006);
      scene.add(m); dots[w.id] = m;
    });
    // probe + beam
    const probe = new THREE.Group();
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.11, 0.022), new THREE.MeshStandardMaterial({ color: 0xe9eef0, roughness: 0.4 }));
    body.position.y = 0.06; probe.add(body);
    const nose = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.022, 20, 1, false, 0, Math.PI), new THREE.MeshStandardMaterial({ color: 0x2a3033, roughness: 0.5 }));
    nose.rotation.x = Math.PI / 2; nose.rotation.z = Math.PI / 2; nose.position.y = 0.006; probe.add(nose);
    const mark = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.02, 0.026), new THREE.MeshBasicMaterial({ color: 0x0fd4c4 }));
    mark.position.set(0.027, 0.06, 0); probe.add(mark);
    const fanG = new THREE.CircleGeometry(0.3, 28, -Math.PI / 2 - 0.6, 1.2);
    const fan = new THREE.Mesh(fanG, new THREE.MeshBasicMaterial({ color: 0x0fd4c4, transparent: true, opacity: 0.22, side: THREE.DoubleSide, depthWrite: false }));
    fan.position.y = 0.0;
    probe.add(fan);
    const fanEdge = new THREE.LineSegments(new THREE.EdgesGeometry(fanG), new THREE.LineBasicMaterial({ color: 0x0fd4c4, transparent: true, opacity: 0.6 }));
    fan.add(fanEdge);
    scene.add(probe);
    let dirty = true, last = 0;
    const api = {
      set(p) {
        if (!p) return;
        const s = surf(p.x, p.y);
        probe.visible = p.contact !== false;
        probe.position.copy(s.p).addScaledVector(s.n, p.contact === false ? 0.05 : 0.0);
        // orient: probe +Y along the surface normal (beam into the body), marker (+X) by rotation
        const up = s.n.clone();
        const head = new THREE.Vector3(0, 0, 1);
        const right = new THREE.Vector3().crossVectors(head, up).normalize();   // toward the patient's right side
        const ang = (p.rot || 0) * Math.PI / 180;
        const markDir = head.clone().multiplyScalar(Math.cos(ang)).addScaledVector(right, Math.sin(ang)).normalize();
        const tiltAx = new THREE.Vector3().crossVectors(up, markDir).normalize();
        const beam = up.clone().negate().applyAxisAngle(tiltAx, -(p.tilt || 0) * Math.PI / 180);
        const yAx = beam.clone().negate();
        const xAx = markDir.clone().addScaledVector(yAx, -markDir.dot(yAx)).normalize();
        const zAx = new THREE.Vector3().crossVectors(xAx, yAx);
        probe.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(xAx, yAx, zAx));
        dirty = true;
      },
      marks(m, cur) {
        WINS.forEach(w => {
          const c = m[w.id] === 'pos' ? 0xff5a5f : m[w.id] === 'neg' ? 0x0fd4c4 : (cur === w.id ? 0xffffff : 0x6b7479);
          dots[w.id].material.color.setHex(c);
          dots[w.id].scale.setScalar(cur === w.id ? 1.5 : 1);
        });
        dirty = true;
      },
      render(now) {
        if (!dirty && now - last < 500) return;
        last = now; dirty = false;
        skin.rotation.z = 0;
        renderer.render(scene, cam);
      },
      destroy() {
        scene.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
        renderer.dispose();
        try { renderer.forceContextLoss(); } catch (e) { /* context already gone */ }
      },
    };
    return api;
  }

  /* ─────────── torso pictogram with the 6 protocol nodes ─────────── */
  const MAPX = x => 60 + x * 33, MAPY = y => 136 - y * 112;
  function mapSVG() {
    const nodes = WINS.map(w => `<g class="nd" data-w="${w.id}" transform="translate(${MAPX(w.x).toFixed(1)} ${MAPY(w.y).toFixed(1)})">
        <circle class="hit" r="11"/><circle class="rg" r="7.5"/><circle class="ct" r="2.6"/><path class="ok" d="M-3 0.2l2 2 4-4.4"/><path class="pl" d="M-3 0h6M0 -3v6"/>
        <text class="lb" y="${w.y > 0.8 ? -12 : w.x < -0.5 ? -12 : w.x > 0.5 ? -12 : 17}">${esc(wShort(w.id))}</text></g>`).join('');
    return `<svg class="mp-svg" viewBox="0 0 120 150">
      <defs><linearGradient id="usTorso" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0fd4c4" stop-opacity=".16"/><stop offset="1" stop-color="#0fd4c4" stop-opacity=".03"/></linearGradient></defs>
      <path class="tor" d="M36 8 C30 9 23 11 20 17 C17 25 22 38 23 50 C24 62 23 74 25 86 C27 100 22 112 24 126 C25 136 33 143 60 144 C87 143 95 136 96 126 C98 112 93 100 95 86 C97 74 96 62 97 50 C98 38 103 25 100 17 C97 11 90 9 84 8 C76 12 68 14 60 14 C52 14 44 12 36 8 Z"/>
      <path class="ln" d="M60 16 V78 M36 31 C44 35 52 36 60 36 C68 36 76 35 84 31 M30 44 C42 50 52 52 60 52 C68 52 78 50 90 44 M33 58 C44 63 52 64 60 64"/>
      <path class="ln" d="M60 64 C68 64 76 63 87 58 M43 78 C50 80 55 81 60 81 C65 81 70 80 77 78"/>
      <circle class="umb" cx="60" cy="98" r="1.6"/>
      <g class="pr"><rect x="-4" y="-6.5" width="8" height="13" rx="2.5"/><circle class="pm" cx="0" cy="-5" r="1.5"/></g>
      ${nodes}
    </svg>`;
  }

  /* ─────────── device face ─────────── */
  // opts = { seed, labels, study, patient, onCaliper(mm), onMark(win, mark), clickable }
  function Device(host, opts = {}) {
    const el = document.createElement('section');
    el.className = 'us-dev';
    el.innerHTML = `
      <div class="dv-shell">
        <i class="dv-screw s1"></i><i class="dv-screw s2"></i><i class="dv-screw s3"></i><i class="dv-screw s4"></i>
        <header class="dv-top">
          <span class="dv-led"></span>
          <span class="dv-model"><b>POCUS-7</b><em>${esc(T('dev_sub', 'portable trauma ultrasound'))}</em></span>
          <span class="dv-probe"><i></i>C5-2</span>
          <span class="dv-batt"><i style="width:78%"></i></span>
        </header>
        <div class="dv-screen">
          <div class="sc-hdr">
            <span class="ps">${esc(T('preset', 'TRAUMA · eFAST'))}</span>
            <span class="mi">MI <b>0.8</b></span><span class="mi">TIs <b>0.4</b></span><span class="mi fq">3.5 <b>MHz</b></span>
            <span class="sid">${esc(opts.study || 'US-00000')}</span>
            <span class="st"><i></i><b class="stt">${esc(T('live', 'LIVE'))}</b></span>
            <span class="clk">--:--:--</span>
          </div>
          <div class="sc-main">
            <div class="sc-img">
              <div class="bm-wrap"><canvas class="bm" width="440" height="372"></canvas><svg class="ov" viewBox="0 0 440 372" preserveAspectRatio="none"></svg></div>
              <div class="mm-wrap"><canvas class="mm" width="440" height="150"></canvas><span class="mm-tag"></span></div>
              <div class="sc-flag"></div>
              <div class="sc-noc"><span>${esc(T('no_contact', 'Probe off the skin'))}</span></div>
            </div>
            <aside class="sc-side">
              <div class="sd-win"><div class="wl">${esc(T('view', 'VIEW'))}</div><div class="wn">—</div><div class="wq"><i></i><i></i><i></i><i></i><i></i><span></span></div></div>
              <div class="sd-3d"><canvas class="v3" width="216" height="118"></canvas><span class="t3">${esc(T('orient', 'PROBE'))}</span></div>
              <div class="sd-map">${mapSVG()}<div class="mp-cnt"><b>0</b>/6</div></div>
              <div class="sd-ndl"></div>
            </aside>
          </div>
          <div class="sc-foot">
            <div class="ft-ecg"><canvas class="ecg" width="260" height="46"></canvas><span class="ecl">II</span></div>
            <div class="ft-hr"><span class="k">HR</span><b class="hr">--</b><span class="rh">--</span></div>
            <div class="ft-acq">
              <span><em>D</em><b class="a-d">16</b>cm</span><span><em>G</em><b class="a-g">55</b>%</span><span><em>F</em><b class="a-f">8</b>cm</span><span><em>DR</em><b>60</b></span><span><em>FPS</em><b class="a-fps">22</b></span>
            </div>
          </div>
        </div>
        <div class="dv-keys">
          <button class="dk" data-k="freeze"><span>${esc(T('k_freeze', 'FREEZE'))}</span><kbd>Space</kbd></button>
          <button class="dk" data-k="mode"><span>B / M</span><kbd>M</kbd></button>
          <button class="dk" data-k="cal"><span>${esc(T('k_measure', 'MEASURE'))}</span><kbd>C</kbd></button>
          <span class="dk-sep"></span>
          <button class="dk sm" data-k="depth-"><span>${esc(T('k_depth', 'DEPTH'))} −</span><kbd>↑</kbd></button>
          <button class="dk sm" data-k="depth+"><span>${esc(T('k_depth', 'DEPTH'))} +</span><kbd>↓</kbd></button>
          <button class="dk sm" data-k="gain-"><span>${esc(T('k_gain', 'GAIN'))} −</span><kbd>←</kbd></button>
          <button class="dk sm" data-k="gain+"><span>${esc(T('k_gain', 'GAIN'))} +</span><kbd>→</kbd></button>
        </div>
        <span class="dv-sticker"><i>!</i>${esc(T('sticker', 'Rx only · IPX7 probe'))}</span>
      </div>`;
    host.appendChild(el);
    const q = s => el.querySelector(s);
    const bm = q('.bm'), ov = q('.ov'), mm = q('.mm'), ecgC = q('.ecg'), v3 = q('.v3');
    const engine = U.BMode(bm, { seed: opts.seed || 7 });
    const mctx = mm.getContext('2d');
    mctx.fillStyle = '#000'; mctx.fillRect(0, 0, mm.width, mm.height);
    let orient = null;
    try { orient = Orient(v3); } catch (e) { orient = null; }
    if (!orient) q('.sd-3d').classList.add('off');
    let trace = null;
    try { trace = NZA.vitals && NZA.vitals.Trace ? NZA.vitals.Trace(ecgC, { type: 'ecg', rhythm: 'sinus', rate: 80, color: '#3ddc84' }) : null; } catch (e) { trace = null; }
    const state = { win: null, flip: false, mmode: false, cal: false, calPts: [], measures: {}, marks: {}, labels: opts.labels !== false, needle: null, fps: 22 };
    let lastLabels = 0, mAcc = 0;

    el.querySelectorAll('.dk').forEach(b => b.addEventListener('click', () => opts.onKey && opts.onKey(b.dataset.k)));
    el.querySelectorAll('.mp-svg .nd').forEach(g => g.addEventListener('click', () => opts.onNode && opts.onNode(g.dataset.w)));

    // calipers on a frozen image
    const bmWrap = q('.bm-wrap');
    bmWrap.addEventListener('mousedown', e => {
      if (e.button !== 0 || !state.cal || !engine.st.frozen) return;
      e.preventDefault(); e.stopPropagation();
      const r = bm.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width * bm.width, py = (e.clientY - r.top) / r.height * bm.height;
      const fx = state.flip ? bm.width - px : px;
      const w = engine.fromPx(fx, py);
      if (!w) return;
      if (state.calPts.length >= 2) state.calPts = [];
      state.calPts.push({ px: fx, py, x: w[0], z: w[1] });
      if (state.calPts.length === 2) {
        const a = state.calPts[0], b = state.calPts[1];
        const mmv = Math.round(Math.hypot(a.x - b.x, a.z - b.z) * 10);
        if (state.win) state.measures[state.win] = mmv;
        opts.onCaliper && opts.onCaliper(mmv, state.win);
        NZA.audio.click(900);
      } else NZA.audio.click(700);
      drawOverlay(true);
    });

    function drawOverlay(force) {
      const now = performance.now();
      if (!force && now - lastLabels < 66) return;
      lastLabels = now;
      const W = bm.width, Hh = bm.height, st = engine.st, sec = engine.sector();
      const fx = x => (state.flip ? W - x : x);
      let s = '';
      // depth ruler (right) with the focal marker
      const rx = W - 14;
      for (let z = 0; z <= st.depth + 0.01; z += 1) {
        const y = engine.toPx(0, z)[1];
        const big = z % 5 === 0;
        s += `<line class="tk" x1="${rx - (big ? 9 : 5)}" y1="${y.toFixed(1)}" x2="${rx}" y2="${y.toFixed(1)}"/>`;
        if (big && z > 0) s += `<text class="tx" x="${rx - 12}" y="${(y + 3.5).toFixed(1)}" text-anchor="end">${z}</text>`;
      }
      const fy = engine.toPx(0, st.focus)[1];
      s += `<path class="fc" d="M${rx + 2} ${fy.toFixed(1)} l7 -5 v10 z"/>`;
      // TGC curve (left)
      let tg = '';
      for (let i = 0; i <= 8; i++) { const y = lerp(sec.y0, sec.y0 + st.depth * sec.k, i / 8); tg += `${i ? 'L' : 'M'}${(12 + (st.gain - 30) * 0.12 + Math.sin(i * 0.9) * 2).toFixed(1)} ${y.toFixed(1)}`; }
      s += `<path class="tgc" d="${tg}"/>`;
      // probe orientation marker (top corner of the sector on the marker side)
      const mk = engine.toPx(-sec.R0 * Math.sin(sec.HALF) * 1.6 - 0.9, sec.zTop - 0.1);
      s += `<g class="mk" transform="translate(${fx(mk[0]).toFixed(1)} ${(mk[1] + 4).toFixed(1)})"><circle r="4.2"/><circle r="1.6" class="in"/></g>`;
      // M-line
      if (state.mmode) {
        const a = engine.toPx(0, 0), b = engine.toPx(0, st.depth);
        s += `<line class="mline" x1="${fx(a[0])}" y1="${a[1]}" x2="${fx(b[0])}" y2="${b[1]}"/>`;
      }
      // anatomy labels
      if (state.labels && st.scene && st.scene.labels && st.contact && st.q > 0.45) {
        const L = st.scene.labels(st) || [];
        L.forEach(l => {
          const p = engine.toPx(l.x, l.z);
          if (p[1] < sec.y0 + 6 || p[1] > Hh - 6 || p[0] < 8 || p[0] > W - 30) return;
          if (!engine.fromPx(p[0], p[1])) return;
          const txt = T('lab_' + l.k, LABELS[l.k] || l.k);
          s += `<text class="lab ${l.small ? 'sm' : ''} ${l.tone || ''}" x="${fx(p[0]).toFixed(1)}" y="${p[1].toFixed(1)}" text-anchor="middle">${esc(txt)}</text>`;
        });
      }
      // needle guide (pericardiocentesis)
      if (state.needle && state.needle.guide) {
        const n = state.needle;
        const a = engine.toPx(n.ex, n.ez), b = engine.toPx(n.ex + Math.sin(n.ang) * 16, n.ez + Math.cos(n.ang) * 16);
        s += `<line class="ng" x1="${fx(a[0]).toFixed(1)}" y1="${a[1].toFixed(1)}" x2="${fx(b[0]).toFixed(1)}" y2="${b[1].toFixed(1)}"/>`;
        if (n.on) {
          for (let d = 1; d <= 14; d++) {
            const p = engine.toPx(n.ex + Math.sin(n.ang) * d, n.ez + Math.cos(n.ang) * d);
            s += `<circle class="ngd ${d <= n.depth ? 'in' : ''}" cx="${fx(p[0]).toFixed(1)}" cy="${p[1].toFixed(1)}" r="${d % 5 ? 1.2 : 2}"/>`;
          }
        }
      }
      // calipers
      state.calPts.forEach((p, i) => {
        s += `<g class="cal" transform="translate(${fx(p.px).toFixed(1)} ${p.py.toFixed(1)})"><path d="M-5 0h10M0 -5v10"/><text x="7" y="-6">${i ? '2' : '1'}</text></g>`;
      });
      if (state.calPts.length === 2) {
        const a = state.calPts[0], b = state.calPts[1];
        const mmv = Math.round(Math.hypot(a.x - b.x, a.z - b.z) * 10);
        s += `<line class="cl" x1="${fx(a.px).toFixed(1)}" y1="${a.py.toFixed(1)}" x2="${fx(b.px).toFixed(1)}" y2="${b.py.toFixed(1)}"/>`;
        const mx = (fx(a.px) + fx(b.px)) / 2, my = (a.py + b.py) / 2;
        s += `<g class="cv" transform="translate(${clamp(mx + 10, 10, W - 120).toFixed(1)} ${clamp(my - 12, 18, Hh - 10).toFixed(1)})"><rect x="-4" y="-13" width="${mmv >= 100 ? 92 : 84}" height="18" rx="3"/><text x="0" y="0">D1  ${(mmv / 10).toFixed(1)} cm</text></g>`;
      }
      ov.innerHTML = s;
    }

    const LABELS = {
      liver: 'LIVER', spleen: 'SPLEEN', kidney: 'KIDNEY', diaphragm: 'DIAPHRAGM', pleural: 'FLUID ABOVE DIAPHRAGM', spine: 'SPINE',
      free_ruq: "FLUID · MORISON'S", free_luq: 'FLUID · SPLENORENAL', free_pelvis: 'FREE FLUID', bladder: 'BLADDER', uterus: 'UTERUS',
      prostate: 'PROSTATE', rv: 'RV', lv: 'LV', ra: 'RA', la: 'LA', effusion: 'EFFUSION', rib: 'RIB', pleura: 'PLEURA',
    };

    function frameM() {
      // scroll the M-mode trace 2 px and paint the newest column
      const w = mm.width, h = mm.height;
      const col = engine.mline(h);
      mctx.drawImage(mm, -2, 0);
      const img = mctx.createImageData(2, h);
      for (let i = 0; i < h; i++) {
        const v = col[i] * 255;
        for (let k = 0; k < 2; k++) { const p = (i * 2 + k) * 4; img.data[p] = v * 0.97; img.data[p + 1] = v * 0.99; img.data[p + 2] = v; img.data[p + 3] = 255; }
      }
      mctx.putImageData(img, w - 2, 0);
    }

    let clockT = 0;
    const api = {
      el, engine, state, q,
      set(p) {
        if (p.labels !== undefined) state.labels = p.labels;
        if (p.flip !== undefined && p.flip !== state.flip) { state.flip = p.flip; bm.style.transform = state.flip ? 'scaleX(-1)' : ''; }
        engine.set(p.engine || {});
        if (p.contact !== undefined) el.classList.toggle('noc', !p.contact);
        return api;
      },
      frame(dt, now) {
        engine.frame(dt);
        if (state.mmode && !engine.st.frozen) { mAcc += dt; while (mAcc > 0.03) { frameM(); mAcc -= 0.03; } }
        drawOverlay(false);
        if (orient) orient.render(now || performance.now());
        if (now - clockT > 1000) {
          clockT = now;
          const d = new Date();
          q('.clk').textContent = d.toTimeString().slice(0, 8);
          q('.a-fps').textContent = String(Math.round(state.fps));
        }
      },
      window(id, qv, name) {
        state.win = id;
        q('.wn').textContent = name || (id ? wName(id) : T('searching', 'Searching…'));
        const bars = el.querySelectorAll('.wq i');
        const n = Math.round(clamp(qv, 0, 1) * 5);
        bars.forEach((b, i) => { b.className = i < n ? (n >= 4 ? 'on' : n >= 2 ? 'mid' : 'low') : ''; });
        q('.wq span').textContent = `${Math.round(clamp(qv, 0, 1) * 100)}%`;
        el.querySelectorAll('.mp-svg .nd').forEach(g => g.classList.toggle('cur', g.dataset.w === id && qv > 0.25));
      },
      probeDot(x, y, rot, contact) {
        const g = el.querySelector('.mp-svg .pr');
        g.style.display = contact ? '' : 'none';
        g.setAttribute('transform', `translate(${MAPX(x).toFixed(1)} ${MAPY(y).toFixed(1)}) rotate(${(-rot).toFixed(0)})`);
        if (orient) orient.set({ x, y, rot, tilt: engine.st.tilt || 0, contact });
      },
      marks(m, extra) {
        state.marks = m;
        let n = 0;
        el.querySelectorAll('.mp-svg .nd').forEach(g => {
          const v = m[g.dataset.w];
          g.classList.toggle('pos', v === 'pos'); g.classList.toggle('neg', v === 'neg');
          const r = extra && extra[g.dataset.w];
          g.classList.toggle('miss', r === 'missed' || r === 'false');
          g.classList.toggle('good', r === 'correct' || r === 'guess' || r === 'auto');
          if (v) n++;
        });
        q('.mp-cnt b').textContent = String(n);
        if (orient) orient.marks(m, state.win);
      },
      seen(map) { el.querySelectorAll('.mp-svg .nd').forEach(g => g.classList.toggle('seen', !!map[g.dataset.w])); },
      freeze(on) {
        engine.set({ frozen: on });
        el.classList.toggle('frozen', on);
        q('.stt').textContent = on ? T('frozen', 'FROZEN') : T('live', 'LIVE');
        if (!on) { state.calPts = []; state.cal = false; el.classList.remove('cal'); }
        drawOverlay(true);
      },
      calipers(on) { state.cal = on && engine.st.frozen; el.classList.toggle('cal', state.cal); if (!state.cal) state.calPts = []; drawOverlay(true); return state.cal; },
      mmode(on) {
        state.mmode = on;
        el.classList.toggle('mmode', on);
        q('.mm-tag').textContent = '';
        drawOverlay(true);
      },
      mtag(text, tone) { const t = q('.mm-tag'); t.textContent = text || ''; t.className = `mm-tag ${tone || ''}`; },
      acq() { const st = engine.st; q('.a-d').textContent = String(st.depth); q('.a-g').textContent = String(Math.round(st.gain)); q('.a-f').textContent = String(Math.round(st.focus)); drawOverlay(true); },
      vitals(v) {
        if (!v) return;
        const hr = Math.round(v.hr || v.ecgRate || 0);
        q('.hr').textContent = hr > 0 ? String(hr) : '--';
        const rh = String(v.rhythm || 'sinus');
        q('.rh').textContent = T('rh_' + rh, RHY[rh] || rh.toUpperCase());
        el.classList.toggle('alarm', rh === 'vf' || rh === 'vt' || rh === 'asystole' || rh === 'pea');
        if (trace && trace.set) trace.set({ rhythm: rh, rate: Math.max(hr, rh === 'asystole' ? 0 : 20) });
        engine.set({ hr: hr || 80, rhythm: rh, rr: v.rr || 14, arrest: rh === 'asystole' || rh === 'pea' });
      },
      ectopic() { if (trace && trace.set) { trace.set({ rhythm: 'vt' }); clearTimeout(api._ect); api._ect = setTimeout(() => trace.set({ rhythm: engine.st.rhythm || 'sinus' }), 700); } },
      flag(text, tone) { const f = q('.sc-flag'); f.innerHTML = text ? `<span class="${tone || ''}">${R(text)}</span>` : ''; },
      ndl(html) { q('.sd-ndl').innerHTML = html || ''; el.classList.toggle('needle', !!html); },
      overlay: () => drawOverlay(true),
      destroy() {
        if (trace && trace.stop) trace.stop();
        if (orient) orient.destroy();
        clearTimeout(api._ect);
        el.remove();
      },
    };
    const RHY = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYSTOLE' };
    api.acq();
    return api;
  }

  /* ─────────── treatment plan (top-left) ─────────── */
  const PLAN = {
    bleeding:   { icon: 'drop', t: ['plan_bleeding', 'Control the bleeding'], d: ['plan_bleeding_d', 'Pressure, packing or a tourniquet on: %s.'] },
    decompress: { icon: 'needle', t: ['plan_decomp', 'Release the trapped air · %s'], d: ['plan_decomp_d', 'Needle in the 2nd rib space, middle of the collarbone. Do this before anything else in the chest.'] },
    chestdrain: { icon: 'tube', t: ['plan_drain', 'Chest drain · %s side'], d: ['plan_drain_d', 'Cut over the 6th rib in the armpit line, clamp through, feed the tube. Drains %s and lets the lung open.'] },
    pericardio: { icon: 'heart', t: ['plan_peri', 'Drain the blood around the heart'], d: ['plan_peri_d', 'Probe under the breastbone, needle toward the left shoulder, draw the blood off. Keep clear of the heart wall.'] },
    angio:      { icon: 'flask', t: ['plan_angio', 'Find and seal the bleeding vessel'], d: ['plan_angio_d', 'Blood in the belly: book angiography (or theatre) to coil the source.'] },
    fragments:  { icon: 'forceps', t: ['plan_frag', 'Remove what is still inside'], d: ['plan_frag_d', 'Bullet or fragments left in: %s. Surgical removal once stable.'] },
  };
  const regionLabel = r => T('rg_' + r, String(r || '').replace(/_/g, ' '));
  // items: { key: n } ; inv: { key: { label, count } }
  function chips(items, inv) {
    return Object.entries(items || {}).map(([k, n]) => {
      const it = (inv && inv[k]) || { label: k.replace(/_/g, ' '), count: 0 };
      const have = (it.count || 0) >= n;
      return `<span class="ch ${have ? 'have' : 'need'}">${icon(have ? 'check' : 'x')}<b>${esc(it.label)}</b><em>${it.count || 0}/${n}</em></span>`;
    }).join('');
  }
  function Plan(host) {
    const el = document.createElement('section');
    el.className = 'us-plan nza-hud solid';
    host.appendChild(el);
    let handler = null;
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (b && handler) handler(b.dataset.act, b.dataset.side || null);
    });
    return {
      el,
      onAction(fn) { handler = fn; },
      render(steps, o = {}) {
        const list = steps || [];
        const body = list.length ? list.map((s, i) => {
          const P = PLAN[s.kind] || PLAN.bleeding;
          const side = s.side ? T('side_' + s.side, s.side) : '';
          const regs = (s.regions || []).map(regionLabel).filter((v, j, a) => a.indexOf(v) === j).join(', ');
          const what = s.cause === 'pneumothorax' ? T('plan_air', 'the air') : T('plan_blood', 'the blood');
          const title = T(P.t[0], P.t[1], side);
          const text = s.kind === 'chestdrain' ? T(P.d[0], P.d[1], what) : T(P.d[0], P.d[1], regs || side);
          const canGo = s.action && o.perms && o.perms[s.action] && !o.done;
          const tone = s.missed ? 'miss' : s.done ? 'done' : '';
          return `<li class="st ${tone}" style="animation-delay:${i * 60}ms">
            <span class="no">${s.done ? icon('check') : String(i + 1).padStart(2, '0')}</span>
            <div class="bd">
              <div class="tt">${icon(P.icon)}<b>${esc(title)}</b>${s.missed ? `<span class="tag">${esc(T('plan_missed', 'missed on scan'))}</span>` : ''}</div>
              <p>${esc(text)}</p>
              ${Object.keys(s.items || {}).length ? `<div class="chs">${chips(s.items, o.inv)}</div>` : ''}
              ${canGo ? `<button class="go" data-act="${esc(s.action)}" ${s.side ? `data-side="${esc(s.side)}"` : ''}>${icon('play')}<span>${esc(T('plan_go', 'Do it now'))}</span></button>` : ''}
            </div></li>`;
        }).join('') : `<li class="st empty"><span class="no">${icon('check')}</span><div class="bd"><div class="tt"><b>${esc(T('plan_none', 'Nothing urgent found yet'))}</b></div><p>${esc(T('plan_none_d', 'Call each window positive or negative. Steps appear here as you find problems.'))}</p></div></li>`;
        el.innerHTML = `
          <header class="pl-hd"><span class="k">${esc(T('plan_kicker', 'Treatment plan'))}</span><span class="n">${list.length}</span></header>
          <div class="pl-sub">${esc(o.sub || T('plan_sub', 'Built from what you called on this scan · in order'))}</div>
          <ol class="pl-list nza-scroll">${body}</ol>
          <div class="pl-note"><span>${esc(T('plan_note', 'Scan again after each step: problems you fixed drop off the screen.'))}</span></div>`;
      },
      destroy() { el.remove(); },
    };
  }

  U.ui = { T, setLocale(l) { LOC = Object.assign({}, l || {}); }, loc: () => LOC, WINS, WIN, wName, wShort, probeView, screenToTorso, torsoToScreen, GX, GY, Device, Plan, chips, regionLabel, angDiff, SX, SY };
})();

/* ═══════════════════════════════════════════════════════════
   Part 3 · scan (eFAST) and pericardiocentesis controllers
   A mode = { key(e) → bool, keyUp(e), msg: { … }, frame(dt, now), destroy() }
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA || !window.NZA.app || !window.NZUS || !window.NZUS.ui) return;
  const U = window.NZUS, UI = U.ui;
  const { clamp, lerp, smooth } = U;
  const T = (...a) => UI.T(...a);
  const esc = NZA.esc, icon = NZA.icon;
  const ORDER = ['ruq', 'luq', 'pelvis', 'cardiac', 'lung_r', 'lung_l'];
  const WTXT = {
    ruq: ['t_ruq', 'Slide onto the **right flank**, low ribs, marker toward the head. Look for a **black stripe** between liver and kidney, or black above the diaphragm.'],
    luq: ['t_luq', 'Go further back on the **left flank**, higher than on the right. Check around the **spleen**, under the diaphragm and above it.'],
    pelvis: ['t_pelvis', 'Just above the **pubic bone**, marker to the patient\'s right. Blood collects as **black corners** behind the bladder.'],
    cardiac: ['t_cardiac', 'Under the **breastbone**, probe flat, aimed at the left shoulder. A **black ring** around the heart means blood in the sac.'],
    lung_r: ['t_lung_r', 'Upper **right chest**, between two ribs, marker to the head. The bright line should **shimmer**. Use {M} to check.'],
    lung_l: ['t_lung_l', 'Upper **left chest**, between two ribs. No shimmer and a **barcode** in M-mode means air outside the lung.'],
  };

  /* ═════════════ SCAN ═════════════ */
  function ScanMode(app, d) {
    const root = app.ui;
    const views = d.views || {};
    const sex = d.patient && d.patient.sex;
    const seed = (d.seed || 4512) >>> 0;
    const scenes = {};
    const sceneFor = w => scenes[w] || (scenes[w] = U.scene(w, Object.assign({ sex }, views[w] || {}), seed));
    const dev = UI.Device(root, {
      seed, labels: d.labels !== false, study: d.study,
      onKey: k => act(k), onNode: w => cycleMark(w), onCaliper: mm => onCaliper(mm),
    });
    const plan = UI.Plan(root);
    plan.onAction((action, side) => launch(action, side));
    const ppHost = document.createElement('div');
    ppHost.className = 'us-pp';
    root.appendChild(ppHost);
    const reticle = document.createElement('div');
    reticle.className = 'us-ret';
    reticle.innerHTML = `<svg viewBox="-40 -40 80 80"><g class="fp"><rect x="-17" y="-6" width="34" height="12" rx="6"/><circle class="mk" cx="13" cy="0" r="2.4"/></g><circle class="rg" r="26"/></svg><span class="lb"></span>`;
    root.appendChild(reticle);
    const markersLayer = document.createElement('div');
    markersLayer.className = 'us-wm';
    markersLayer.innerHTML = ORDER.map(w => `<div class="wm" data-w="${w}"><i></i><span>${esc(UI.wShort(w))}</span></div>`).join('');
    root.appendChild(markersLayer);

    const S = {
      p: { x: 0, y: 0.5, rot: 0, tilt: 0, contact: false }, tgt: { x: 0, y: 0.5 }, rotT: 0, tiltT: 0,
      marks: {}, seen: {}, measure: {}, view: null, frozen: false, mmode: false, cal: false,
      depthBy: {}, gainBy: {}, autoDone: {}, mouse: null, sendT: 0, uiT: 0, hint: '', done: false, finishing: false,
      vit: Object.assign({}, d.vitals || {}), acc: 0,
    };
    const minSeen = d.minSeen || 1.2;
    dev.engine.set({ depth: 16, focus: 9, gain: 55 });
    dev.vitals(S.vit);

    const steps = ORDER.map(w => UI.wName(w)).concat([T('step_read', 'Read the scan')]);
    const pp = NZA.ui.ProcPanel(ppHost, {
      tag: T('scan_tag', 'eFAST · bedside ultrasound'), step: 1, total: 7, steps,
      title: UI.wName('ruq'), text: T(WTXT.ruq[0], WTXT.ruq[1]),
      wide: { label: T('quality', 'Image'), value: '0', unit: '%', meter: { value: 0, zone: [0.6, 1] }, caption: T('no_probe', 'probe not on the skin') },
      stats: [
        { id: 'win', label: T('st_window', 'Window'), value: '—', small: true },
        { id: 'rot', label: T('st_rot', 'Marker'), value: '0°' },
        { id: 'seen', label: T('st_called', 'Called'), value: '0/6' },
      ],
      tools: tools(),
      hints: [
        { keys: [T('k_mouse', 'Mouse')], label: T('h_slide', 'slide the probe') },
        { keys: [T('k_wheel', 'Wheel')], label: T('h_rotate', 'turn the marker') },
        { keys: ['Q', 'E'], label: T('h_tilt', 'tilt') },
        { keys: ['↑', '↓'], label: T('h_depth', 'depth') },
        { keys: ['←', '→'], label: T('h_gain', 'gain') },
        { keys: [T('k_rmb', 'RMB')], label: T('h_look', 'look around') },
      ],
      abort: { label: T('hold_stop', 'Hold to put the probe down'), key: 'ESC', seconds: 1.2 },
      onAbort: () => app.abort(),
      onTool: k => act(TOOLKEY[k] || k),
    });
    const TOOLKEY = { Space: 'freeze', C: 'cal', M: 'mode', P: 'pos', N: 'neg', Enter: 'finish' };
    function tools() {
      const w = S.view && S.view.qPos > 0.3 && S.p.contact ? S.view.win.id : null;
      const all = ORDER.every(x => S.marks[x]);
      return [
        { key: 'Space', label: T('tl_freeze', 'Freeze'), icon: 'snow', state: S.frozen ? 'active' : '' },
        { key: 'C', label: T('tl_measure', 'Measure'), icon: 'ruler', state: S.cal ? 'active' : S.frozen ? '' : 'locked' },
        { key: 'M', label: T('tl_mmode', 'M-mode'), icon: 'pulse', state: S.mmode ? 'active' : '' },
        { key: 'P', label: T('tl_pos', 'Call positive'), sub: w ? UI.wShort(w) : '', icon: 'plus', state: w ? (S.marks[w] === 'pos' ? 'done' : '') : 'locked' },
        { key: 'N', label: T('tl_neg', 'Call negative'), sub: w ? UI.wShort(w) : '', icon: 'minus', state: w ? (S.marks[w] === 'neg' ? 'done' : '') : 'locked' },
        { key: 'Enter', label: T('tl_finish', 'Finish scan'), icon: 'check', state: all ? 'need' : '' },
      ];
    }
    let toolSig = '';
    function refreshTools() {
      const t = tools();
      const sig = JSON.stringify(t.map(x => [x.state, x.sub]));
      if (sig !== toolSig) { toolSig = sig; pp.set({ tools: t }); }
    }

    // ── plan from the medic's own calls ──
    const SI = d.stepItems || {};
    function derivePlan() {
      const out = (d.plan || []).map(s => Object.assign({}, s));
      const pos = w => S.marks[w] === 'pos';
      const drains = d.drains || {};
      const lowBP = (S.vit.sys || 120) < 92;
      [['lung_r', 'right'], ['lung_l', 'left']].forEach(([w, side]) => {
        if (pos(w) && lowBP) out.push({ id: 'decomp_' + side, kind: 'decompress', side, items: SI.decompress, action: 'decompress', order: 20 });
      });
      const want = {};
      if (pos('ruq') && views.ruq && views.ruq.pleural) want.right = 'haemothorax';
      if (pos('luq') && views.luq && views.luq.pleural) want.left = 'haemothorax';
      if (pos('lung_r') && !want.right) want.right = 'pneumothorax';
      if (pos('lung_l') && !want.left) want.left = 'pneumothorax';
      ['right', 'left'].forEach(side => {
        if (want[side] && !drains[side]) out.push({ id: 'drain_' + side, kind: 'chestdrain', side, cause: want[side], items: SI.chestdrain, action: 'chestdrain', order: 30 });
      });
      if (pos('cardiac')) out.push({ id: 'pericardio', kind: 'pericardio', items: SI.pericardio, action: 'pericardio', order: 40 });
      const belly = ['ruq', 'luq', 'pelvis'].some(w => pos(w) && (!views[w] || views[w].free || !views[w].pleural));
      if (belly) out.push({ id: 'angio', kind: 'angio', items: SI.angio || {}, order: 50 });
      return out.sort((a, b) => (a.order || 99) - (b.order || 99));
    }
    function renderPlan() { plan.render(derivePlan(), { inv: d.inv, perms: d.perms }); }
    renderPlan();

    // ── marks ──
    function setMark(w, m) {
      if (S.done) return;
      if (S.marks[w] === m) delete S.marks[w]; else S.marks[w] = m;
      dev.marks(S.marks);
      renderPlan();
      const n = ORDER.filter(x => S.marks[x]).length;
      pp.set({ step: Math.min(7, n + 1) }).stat('seen', { value: `${n}/6`, tone: n === 6 ? 'teal' : '' });
      if (S.marks[w]) {
        NZA.audio.tone(S.marks[w] === 'pos' ? 520 : 880, 90, { vol: 0.07 });
        pp.flash(S.marks[w] === 'pos' ? 'warn' : 'ok', S.marks[w] === 'pos' ? T('fl_pos', '%s called **positive**.', UI.wShort(w)) : T('fl_neg', '%s called **clear**.', UI.wShort(w)), 2200);
      }
      refreshTools();
      paintMarkers(true);
    }
    function cycleMark(w) {
      if ((S.seen[w] || 0) < 0.3) { pp.flash('warn', T('fl_scan_first', 'Put the probe on %s first.', UI.wShort(w)), 2400); return; }
      const cur = S.marks[w];
      setMark(w, cur === 'pos' ? 'neg' : cur === 'neg' ? 'neg' : 'pos');
    }
    function markCurrent(m) {
      const v = S.view;
      if (!S.p.contact || !v || v.qPos < 0.3) { pp.flash('warn', T('fl_no_window', 'Hold the probe on a window first.'), 2200); return; }
      setMark(v.win.id, m);
    }
    function onCaliper(mmv) {
      S.measure[dev.state.win || 'x'] = mmv;
      pp.flash('ok', T('fl_measured', 'Measured **%s mm**.', mmv), 2400);
    }

    // ── device controls ──
    function act(k) {
      if (S.done && k !== 'finish') return;
      switch (k) {
        case 'freeze': S.frozen = !S.frozen; dev.freeze(S.frozen); if (!S.frozen) S.cal = false; NZA.audio.click(S.frozen ? 600 : 800); break;
        case 'cal': if (!S.frozen) { pp.flash('warn', T('fl_freeze_first', 'Freeze the image ({Space}) before you measure.'), 2400); break; } S.cal = dev.calipers(!S.cal); if (S.cal) pp.flash('info', T('fl_cal', 'Click the two edges of the fluid on the image.'), 3000); break;
        case 'mode': S.mmode = !S.mmode; dev.mmode(S.mmode); NZA.audio.click(700); break;
        case 'pos': markCurrent('pos'); break;
        case 'neg': markCurrent('neg'); break;
        case 'depth-': case 'depth+': setDepth(dev.engine.st.depth + (k === 'depth+' ? 2 : -2)); break;
        case 'gain-': case 'gain+': setGain(dev.engine.st.gain + (k === 'gain+' ? 5 : -5)); break;
        case 'finish': finish(); break;
        default: break;
      }
      refreshTools();
    }
    function setDepth(v) {
      v = clamp(Math.round(v), 6, 24);
      dev.engine.set({ depth: v, focus: clamp(dev.engine.st.focus, 1, v - 1) });
      if (S.view) S.depthBy[S.view.win.id] = v;
      dev.acq();
    }
    function setGain(v) { v = clamp(v, 20, 90); dev.engine.set({ gain: v }); if (S.view) S.gainBy[S.view.win.id] = v; dev.acq(); }

    // ── finish & launch ──
    function result() {
      const seen = {};
      ORDER.forEach(w => { seen[w] = Math.round((S.seen[w] || 0) * 10) / 10; });
      const n = ORDER.filter(w => S.marks[w]).length;
      return { marks: Object.assign({}, S.marks), seen, measure: Object.assign({}, S.measure), score: Math.round(n / 6 * 100) };
    }
    function finish(force) {
      if (S.done || S.finishing) return;
      const missing = ORDER.filter(w => !S.marks[w]);
      if (missing.length && !force) {
        NZA.ui.Modal({
          title: T('m_unfinished', 'Some windows are not called'), icon: 'alert', tone: 'teal',
          text: T('m_unfinished_d', 'Not called yet: **%s**. Unchecked windows count as missed if they hide a problem.', missing.map(UI.wShort).join(', ')),
          host: app.el,
          actions: [{ label: T('m_keep', 'Keep scanning'), kind: 'line' }, { label: T('m_finish', 'Finish anyway'), kind: 'teal', onClick: () => finish(true) }],
        });
        return;
      }
      S.finishing = true;
      pp.set({ title: T('reading', 'Reading the scan…'), text: T('reading_d', 'Comparing your calls with the images.'), tools: [] });
      NZA.post('ultrasound:finish', { result: result() }).then(r => {
        if (r && r.outcome) api.msg.result(r.outcome);
        else if (r && r.ok === false) { S.finishing = false; refreshTools(); pp.flash('bad', (r && r.msg) || T('err_generic', 'Something went wrong.'), 3500); }
      });
    }
    function launch(action, side) {
      if (S.launching) return;
      S.launching = true;
      plan.el.classList.add('busy');
      NZA.post('ultrasound:launch', { action, side, result: result() }).then(r => {
        if (r && r.ok === false) { S.launching = false; plan.el.classList.remove('busy'); pp.flash('bad', r.msg || T('err_generic', 'Something went wrong.'), 3500); }
      });
    }

    // ── pointer → probe ──
    const onMove = e => { S.mouse = { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight, cx: e.clientX, cy: e.clientY }; };
    const onWheel = e => {
      if (e.shiftKey || e.ctrlKey) return;                       // shift / ctrl + wheel = camera zoom (core)
      if (e.target && e.target.closest && e.target.closest('.us-plan,.us-dev .sc-side')) return;
      e.preventDefault();
      S.rotT += Math.sign(e.deltaY) * 15;
    };
    app.el.addEventListener('mousemove', onMove);
    app.el.addEventListener('wheel', onWheel, { passive: false });

    function paintMarkers(force) {
      const A = app.anchors();
      markersLayer.querySelectorAll('.wm').forEach(m => {
        const w = UI.WIN[m.dataset.w];
        const p = UI.torsoToScreen(w.x, w.y, A);
        if (!p || !p.visible) { m.style.display = 'none'; return; }
        m.style.display = '';
        m.style.left = `${(p.x * window.innerWidth / (NZA.zoom || 1)).toFixed(1)}px`;
        m.style.top = `${(p.y * window.innerHeight / (NZA.zoom || 1)).toFixed(1)}px`;
        if (force) {
          m.className = `wm ${S.marks[w.id] || ''} ${(S.seen[w.id] || 0) >= minSeen ? 'seen' : ''} ${S.view && S.view.win.id === w.id && S.view.qPos > 0.3 && S.p.contact ? 'cur' : ''}`;
        }
      });
    }

    function hintFor(v) {
      if (!S.p.contact) return ['nocontact', T('hint_nocontact', 'Move onto the patient to put the probe on the skin.')];
      if (v.qPos < 0.45) return ['find', T('hint_find', 'Slide toward the **%s** marker.', UI.wShort(nextWin()))];
      if (v.rerr > 30) return ['rot', T(v.win.rot === 90 ? 'hint_rot_side' : 'hint_rot_head', v.win.rot === 90 ? 'Turn the marker to the **patient\'s right** ({Wheel}).' : 'Turn the marker toward the **head** ({Wheel}).')];
      if (v.terr > 12) return ['tilt', T('hint_tilt', 'Flatten the probe and aim up under the ribs ({E}).')];
      if (v.q < 0.6) return ['still', T('hint_still', 'Nearly there: small moves until the picture sharpens.')];
      return ['good', T('hint_good', 'Clear view. Call it: {P} fluid / air seen, {N} clear.')];
    }
    function nextWin() { return ORDER.find(w => !S.marks[w]) || 'ruq'; }

    let lastWin = null, lastHintKey = '';
    function updateUI() {
      const v = S.view;
      const cur = v && v.qPos > 0.3 && S.p.contact ? v.win.id : null;
      const target = cur || nextWin();
      const [hk, hint] = v ? hintFor(v) : ['nocontact', T('hint_nocontact', 'Move onto the patient to put the probe on the skin.')];
      if (target !== lastWin || hk !== lastHintKey) {
        lastWin = target; lastHintKey = hk;
        pp.set({ title: UI.wName(target), text: `${T(WTXT[target][0], WTXT[target][1])}` });
        pp.flash(hk === 'good' ? 'ok' : 'info', hint, 0);
      }
      const q = v && S.p.contact ? v.q : 0;
      pp.wide({ value: String(Math.round(q * 100)), meter: { value: q, zone: [0.6, 1], tone: q >= 0.6 ? '' : q > 0.3 ? 'amber' : 'red' }, caption: S.p.contact ? (cur ? UI.wShort(cur) : T('no_window', 'no window')) : T('no_probe', 'probe not on the skin'), captionTone: q >= 0.6 ? 'teal' : '' });
      pp.stat('win', { value: cur ? UI.wShort(cur) : '—' });
      pp.stat('rot', { value: `${Math.round(((S.p.rot % 360) + 360) % 360)}°` });
      dev.window(cur, q, cur ? UI.wName(cur) : (S.p.contact ? T('searching', 'Searching…') : T('no_probe', 'probe not on the skin')));
      const seenMap = {};
      ORDER.forEach(w => { seenMap[w] = (S.seen[w] || 0) >= minSeen; });
      dev.seen(seenMap);
      refreshTools();
      // M-mode reading for the lung windows
      if (S.mmode && cur && cur.startsWith('lung') && q > 0.5) {
        const ptx = views[cur] && views[cur].ptx;
        dev.mtag(ptx ? T('mm_barcode', 'NO SHIMMER · BARCODE') : T('mm_seashore', 'SHIMMER · SEASHORE'), ptx ? 'red' : 'teal');
      } else dev.mtag(S.mmode ? T('mm_line', 'M-LINE · CENTRE') : '', '');
    }

    // ── the frame loop ──
    let fpsAcc = 0, fpsN = 0;
    function frame(dt, now) {
      const A = app.anchors();
      // probe follows the cursor over the torso
      if (S.mouse && !S.done) {
        const t = UI.screenToTorso(S.mouse, A);
        if (t && t.inside && !S.overUi) { S.tgt.x = t.x; S.tgt.y = t.y; S.p.contact = true; } else S.p.contact = false;
      }
      const k = 1 - Math.exp(-dt * 14);
      S.p.x = lerp(S.p.x, S.tgt.x, k); S.p.y = lerp(S.p.y, S.tgt.y, k);
      S.p.rot = lerp(S.p.rot, S.rotT, 1 - Math.exp(-dt * 12));
      S.p.tilt = lerp(S.p.tilt, S.tiltT, 1 - Math.exp(-dt * 12));
      const v = S.view = UI.probeView(S.p.x, S.p.y, S.p.rot, S.p.tilt);
      // which picture
      let sc, q = v.q;
      if (!S.p.contact) sc = null;
      else if (v.qPos < 0.08) sc = sceneFor(S.p.y > 0.8 ? (S.p.x < 0 ? 'lung_r' : 'lung_l') : 'bowel');
      else sc = sceneFor(v.win.id);
      if (sc && v.qPos < 0.08 && S.p.y > 0.8) q = 0.45;
      // presets: first time a window is acquired, jump to its depth / focus
      if (S.p.contact && v.qPos > 0.5 && !S.autoDone[v.win.id]) {
        S.autoDone[v.win.id] = true;
        dev.engine.set({ depth: S.depthBy[v.win.id] || v.win.depth, focus: v.win.focus, gain: S.gainBy[v.win.id] || dev.engine.st.gain });
        dev.acq();
      }
      if (S.p.contact && v.q >= 0.6 && !S.frozen) S.seen[v.win.id] = (S.seen[v.win.id] || 0) + dt;
      dev.set({ contact: S.p.contact, flip: v.flip, engine: { scene: sc || dev.engine.st.scene, contact: S.p.contact, q, shift: v.shift, vis: v.vis, tilt: S.p.tilt, wander: S.p.x * 6 + S.p.y * 9 } });
      // throttle the imaging to ~22 fps
      S.acc += dt;
      if (S.acc >= 0.045 || S.frozen) {
        const fdt = Math.min(S.acc, 0.1);
        S.acc = 0;
        dev.frame(fdt, now);
        fpsAcc += fdt; fpsN++;
        if (fpsAcc > 1) { dev.state.fps = fpsN / fpsAcc; fpsAcc = 0; fpsN = 0; }
      }
      dev.probeDot(S.p.x, S.p.y, S.p.rot, S.p.contact);
      // reticle
      if (S.mouse) {
        const z = NZA.zoom || 1;
        reticle.style.left = `${(S.mouse.cx / z).toFixed(1)}px`; reticle.style.top = `${(S.mouse.cy / z).toFixed(1)}px`;
        reticle.classList.toggle('on', S.p.contact && !S.done);
        reticle.classList.toggle('good', v.q >= 0.6);
        reticle.querySelector('.fp').setAttribute('transform', `rotate(${(-S.p.rot - 90).toFixed(1)})`);
        reticle.querySelector('.lb').textContent = S.p.contact && v.qPos > 0.3 ? UI.wShort(v.win.id) : '';
      }
      // in-world probe (Lua) at ~15 Hz
      S.sendT += dt;
      if (S.sendT > 0.066) {
        S.sendT = 0;
        NZA.post('ultrasound:probe', { x: +S.p.x.toFixed(3), y: +S.p.y.toFixed(3), rot: Math.round(S.p.rot), tilt: Math.round(S.p.tilt), contact: S.p.contact });
      }
      S.uiT += dt;
      if (S.uiT > 0.1) { S.uiT = 0; updateUI(); paintMarkers(true); } else paintMarkers(false);
    }

    const api = {
      key(e) {
        if (S.done) {
          if (e.key === 'Enter') { pp.key(e); return true; }
          return false;
        }
        const c = e.code, key = e.key;
        if (key === ' ' || c === 'Space') { act('freeze'); return true; }
        if (c === 'KeyC') { act('cal'); return true; }
        if (c === 'KeyM') { act('mode'); return true; }
        if (c === 'KeyP') { act('pos'); return true; }
        if (c === 'KeyN') { act('neg'); return true; }
        if (c === 'KeyQ') { S.tiltT = clamp(S.tiltT - 5, -10, 40); return true; }
        if (c === 'KeyE') { S.tiltT = clamp(S.tiltT + 5, -10, 40); return true; }
        if (key === 'ArrowUp') { act('depth-'); return true; }
        if (key === 'ArrowDown') { act('depth+'); return true; }
        if (key === 'ArrowLeft') { act('gain-'); return true; }
        if (key === 'ArrowRight') { act('gain+'); return true; }
        if (key === 'Enter') { act('finish'); return true; }
        return false;
      },
      overUi(v) { S.overUi = v; },
      frame,
      msg: {
        vitals(v) { S.vit = Object.assign(S.vit, v || {}); dev.vitals(S.vit); },
        result(o) {
          if (S.done) return;
          S.done = true; S.finishing = false;
          const res = {};
          const W = (o && o.windows) || {};
          ORDER.forEach(w => { res[w] = W[w] ? W[w].result : null; });
          const truthMarks = {};
          ORDER.forEach(w => { if (W[w]) truthMarks[w] = W[w].pos ? 'pos' : 'neg'; });
          dev.marks(Object.keys(S.marks).length ? S.marks : truthMarks, res);
          const missedW = (o.missed || []);
          const steps = (o.plan || []).map(s => {
            const st = Object.assign({}, s);
            if (s.kind === 'chestdrain') st.missed = missedW.includes(s.side === 'left' ? 'luq' : 'ruq') && missedW.includes(s.side === 'left' ? 'lung_l' : 'lung_r') ? true : missedW.some(w => (s.side === 'left' ? ['luq', 'lung_l'] : ['ruq', 'lung_r']).includes(w));
            if (s.kind === 'pericardio') st.missed = missedW.includes('cardiac');
            if (s.kind === 'angio') st.missed = ['ruq', 'luq', 'pelvis'].every(w => !S.marks[w] || S.marks[w] === 'neg') && missedW.some(w => ['ruq', 'luq', 'pelvis'].includes(w));
            if (s.kind === 'decompress') st.missed = missedW.includes(s.side === 'left' ? 'lung_l' : 'lung_r');
            if (!st.items && SI[s.kind]) st.items = SI[s.kind];
            return st;
          });
          d.drains = o.drains || d.drains;
          plan.render(steps, { inv: d.inv, perms: d.perms, sub: T('plan_sub_final', 'From the full read · in order') });
          const right = ORDER.filter(w => res[w] === 'correct' || res[w] === 'guess' || res[w] === 'auto').length;
          const missed = ORDER.filter(w => res[w] === 'missed');
          const falseCalls = ORDER.filter(w => res[w] === 'false');
          let text;
          if (o.easy) text = T('res_easy', 'Every window read for you. The plan below is complete.');
          else {
            text = T('res_count', '**%s of 6** windows called right.', right);
            if (missed.length) text += ' ' + T('res_missed', 'Missed: **%s**.', missed.map(UI.wShort).join(', '));
            if (falseCalls.length) text += ' ' + T('res_false', 'Called but clear: %s.', falseCalls.map(UI.wShort).join(', '));
          }
          if (o.msg) text += `\n${o.msg}`;
          pp.complete({ title: T('res_title', 'Scan read · %s', o.grade || '-'), text, label: T('done', 'Done'), onDone: () => app.close() });
          pp.wide({ label: T('score', 'Score'), value: String(o.score ?? 0), unit: '', meter: { value: (o.score || 0) / 100, zone: [0.72, 1] }, caption: T('grade', 'grade %s', o.grade || '-'), captionTone: (o.score || 0) >= 72 ? 'teal' : 'amber' });
          dev.flag(T('res_flag', 'Read: %s/6 right', right), missed.length ? 'red' : 'teal');
          NZA.audio[missed.length ? 'fail' : 'success']();
          paintMarkers(true);
        },
        launchFailed(r) { S.launching = false; plan.el.classList.remove('busy'); pp.flash('bad', (r && r.msg) || T('err_generic', 'Something went wrong.'), 3500); },
      },
      destroy() {
        app.el.removeEventListener('mousemove', onMove);
        app.el.removeEventListener('wheel', onWheel);
        pp.destroy(); dev.destroy(); plan.destroy();
        ppHost.remove(); reticle.remove(); markersLayer.remove();
      },
    };
    // pointer over UI panels lifts the probe (no accidental scanning through the device)
    [dev.el, plan.el].forEach(p => {
      p.addEventListener('mouseenter', () => { S.overUi = true; });
      p.addEventListener('mouseleave', () => { S.overUi = false; });
    });
    dev.marks({});
    return api;
  }

  /* ═════════════ PERICARDIOCENTESIS ═════════════ */
  function PeriMode(app, d) {
    const root = app.ui;
    const seed = (d.seed || 4512) >>> 0;
    const view = Object.assign({}, (d.views && d.views.cardiac) || {}, { effusion: d.mm || 12 });
    const scene = U.scene('cardiac', view, seed);
    const dev = UI.Device(root, { seed, labels: d.labels !== false, study: d.study, onKey: k => devKey(k) });
    dev.el.classList.add('peri');
    const ppHost = document.createElement('div');
    ppHost.className = 'us-pp';
    root.appendChild(ppHost);
    const reticle = document.createElement('div');
    reticle.className = 'us-ret';
    reticle.innerHTML = `<svg viewBox="-40 -40 80 80"><g class="fp"><rect x="-17" y="-6" width="34" height="12" rx="6"/><circle class="mk" cx="13" cy="0" r="2.4"/></g><circle class="rg" r="26"/></svg><span class="lb"></span>`;
    root.appendChild(reticle);

    const ml0 = Math.max(10, d.ml || 150);
    const S = {
      phase: 'window', p: { x: 0.3, y: 0.62, rot: 90, tilt: 20, contact: false }, tgt: { x: 0.3, y: 0.62 },
      hold: 0, ang: 0.86, angT: 0.86, depth: 0, lmb: false, rmb: false, f: false,
      ml: ml0, drawn: 0, syr: 0, syrMax: d.syringe || 60, rate: d.drawRate || 7, leftOver: d.leftOver || 20,
      touches: 0, inHeart: false, flash: 0, passes: 0, wasIn: false, t: 0, sendT: 0, uiT: 0, acc: 0, mouse: null, done: false,
      vit: Object.assign({}, d.vitals || {}), hr0: (d.vitals && (d.vitals.hr || d.vitals.ecgRate)) || 118, sys0: (d.vitals && d.vitals.sys) || 82, mmNow: d.mm || 12,
    };
    dev.engine.set({ depth: 18, focus: 9, gain: 55, scene, effusion: S.mmNow });
    dev.vitals(S.vit);
    dev.window('cardiac', 0, UI.wName('cardiac'));
    dev.marks({ cardiac: 'pos' });

    // syringe widget (in the procedure column)
    const syr = document.createElement('div');
    syr.className = 'us-syr nza-hud solid';
    syr.innerHTML = `
      <div class="sy-hd"><span>${esc(T('syr_title', 'Syringe'))}</span><b class="sy-v">0<em> / ${S.syrMax} mL</em></b></div>
      <svg class="sy" viewBox="0 0 300 54">
        <defs><linearGradient id="usBl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9b1418"/><stop offset=".5" stop-color="#6d0b0e"/><stop offset="1" stop-color="#3d0507"/></linearGradient>
          <linearGradient id="usGl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset=".35" stop-color="#fff" stop-opacity=".06"/><stop offset="1" stop-color="#fff" stop-opacity=".12"/></linearGradient></defs>
        <rect class="nd" x="4" y="25" width="34" height="3" rx="1.5"/>
        <path class="hub" d="M38 19h16v16H38z"/>
        <rect class="fl" x="38" y="21" width="16" height="12" rx="2"/>
        <rect class="br" x="54" y="12" width="190" height="30" rx="6"/>
        <rect class="bl" x="56" y="14" width="0" height="26" rx="4" fill="url(#usBl)"/>
        <g class="gr"></g>
        <rect class="pl" x="56" y="12" width="10" height="30" rx="2"/>
        <rect class="rod" x="66" y="24" width="190" height="6" rx="3"/>
        <rect class="thumb" x="250" y="8" width="10" height="38" rx="4"/>
        <rect class="gl" x="54" y="12" width="190" height="30" rx="6" fill="url(#usGl)"/>
      </svg>
      <div class="sy-ft"><span>${esc(T('syr_sac', 'Left around the heart'))}</span><b class="sy-sac">~${Math.round(S.ml)} mL</b></div>`;
    const grad = syr.querySelector('.gr');
    let gs = '';
    for (let i = 0; i <= S.syrMax; i += 5) { const x = 56 + i / S.syrMax * 186; gs += `<line x1="${x.toFixed(1)}" y1="12" x2="${x.toFixed(1)}" y2="${i % 10 ? 18 : 22}"/>${i % 20 === 0 && i ? `<text x="${x.toFixed(1)}" y="9.5">${i}</text>` : ''}`; }
    grad.innerHTML = gs;

    const STEPS = [T('pc_s1', 'Find the heart'), T('pc_s2', 'Needle toward the left shoulder'), T('pc_s3', 'Draw the blood off'), T('pc_s4', 'Needle out')];
    const pp = NZA.ui.ProcPanel(ppHost, {
      tag: T('pc_tag', 'Pericardiocentesis · ultrasound guided'), step: 1, total: 4, steps: STEPS,
      title: STEPS[0], text: T('pc_t1', 'Hold the probe **under the breastbone** until the black ring around the heart is clear, then press {F} to put the needle in beside it.'),
      wide: { label: T('pc_sac', 'Around the heart'), value: String(Math.round(S.ml)), unit: 'mL', meter: { value: 1, zone: [0, S.leftOver / ml0], tone: 'red' }, caption: T('pc_cap', 'drain it below %s mL', S.leftOver) },
      stats: [
        { id: 'tip', label: T('pc_tip', 'Needle tip'), value: '0.0', unit: 'cm' },
        { id: 'drawn', label: T('pc_drawn', 'Drawn'), value: '0', unit: 'mL' },
        { id: 'touch', label: T('pc_touch', 'Heart touched'), value: '0' },
      ],
      tools: tools(),
      hints: [
        { keys: [T('k_mouse', 'Mouse')], label: T('pc_h_aim', 'probe / needle angle') },
        { keys: [T('k_lmb', 'LMB')], label: T('pc_h_adv', 'advance') },
        { keys: [T('k_rmb', 'RMB')], label: T('pc_h_back', 'pull back') },
        { keys: ['F'], label: T('pc_h_draw', 'hold to draw') },
        { keys: ['T'], label: T('pc_h_tap', 'empty the syringe') },
      ],
      abort: { label: T('hold_stop_needle', 'Hold to stop'), key: 'ESC', seconds: 1.2 },
      onAbort: () => app.abort(),
      onTool: k => { if (k === 'F') pressF(); if (k === 'T') empty(); },
    });
    pp.slot.prepend(syr);
    function tools() {
      return [
        { key: 'F', label: S.phase === 'window' ? T('pc_tl_in', 'Needle in') : T('pc_tl_draw', 'Draw back'), icon: 'syringe', state: S.phase === 'window' ? (S.hold > 0.8 ? 'need' : '') : S.f ? 'active' : '' },
        { key: 'LMB', label: T('pc_tl_adv', 'Advance'), icon: 'arrow-r', state: S.phase === 'window' || S.phase === 'out' ? 'locked' : S.lmb ? 'active' : '' },
        { key: 'RMB', label: T('pc_tl_back', 'Pull back'), icon: 'arrow-l', state: S.phase === 'window' ? 'locked' : S.rmb ? 'active' : '' },
        { key: 'T', label: T('pc_tl_tap', 'Empty syringe'), sub: `${Math.round(S.syr)} mL`, icon: 'drop', state: S.syr >= S.syrMax - 0.5 ? 'need' : S.syr > 0 ? '' : 'locked' },
      ];
    }
    let toolSig = '';
    function refreshTools() { const t = tools(); const sig = JSON.stringify(t.map(x => [x.state, x.sub, x.label])); if (sig !== toolSig) { toolSig = sig; pp.set({ tools: t }); } }

    function setPhase(ph) {
      S.phase = ph;
      const idx = { window: 1, needle: 2, draw: 3, out: 4 }[ph];
      const txt = {
        window: T('pc_t1', 'Hold the probe **under the breastbone** until the black ring around the heart is clear, then press {F} to put the needle in beside it.'),
        needle: T('pc_t2', 'Aim with the mouse toward the **left shoulder** (dotted line). Hold {LMB} to advance. Stop when the tip sits in the **black** band.'),
        draw: T('pc_t3', 'Blood in the hub. Hold {F} to draw it off. The sac shrinks and the heart comes closer: ease back with {RMB} so the tip never touches it.'),
        out: T('pc_t4', 'The sac is nearly dry. Hold {RMB} to pull the needle all the way out.'),
      }[ph];
      pp.set({ step: idx, title: STEPS[idx - 1], text: txt });
      refreshTools();
    }
    function pressF() {
      if (S.done) return;
      if (S.phase === 'window') {
        if (S.hold < 0.8) { pp.flash('warn', T('pc_fl_window', 'Get a clear view of the heart first.'), 2200); return; }
        S.p.contact = true;
        setPhase('needle');
        dev.state.needle = { on: true, guide: true, ex: -6.6, ez: 0, ang: S.ang, depth: 0 };
        NZA.audio.click(500);
        app.post('needle', { phase: 'in', depth: 0, ang: S.ang });
      }
    }
    function empty() {
      if (S.syr <= 0 || S.done) return;
      S.syr = 0;
      NZA.audio.noise(380, { vol: 0.06, lp: 900, hp: 200 });
      pp.flash('ok', T('pc_fl_empty', 'Tap turned, syringe emptied into the bowl.'), 2000);
      refreshTools();
    }
    function devKey(k) { if (k === 'freeze') pp.flash('info', T('pc_fl_nofreeze', 'Keep the picture live while the needle is in.'), 2200); }

    const onMove = e => { S.mouse = { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight, cx: e.clientX, cy: e.clientY, mx: e.movementX || 0 }; if (S.phase !== 'window' && !S.done) S.angT = clamp(S.angT + (e.movementX || 0) * 0.0025, 0.45, 1.25); };
    const onDown = e => { if (S.done) return; if (e.button === 0) S.lmb = true; if (e.button === 2) { S.rmb = true; e.preventDefault(); } refreshTools(); };
    const onUp = e => { if (e.button === 0) S.lmb = false; if (e.button === 2) S.rmb = false; refreshTools(); };
    app.el.addEventListener('mousemove', onMove);
    app.el.addEventListener('mousedown', onDown);
    window.addEventListener('mouseup', onUp);

    function ndlHTML(path) {
      const max = 12, h = 150;
      const y = dcm => (clamp(dcm, 0, max) / max * h).toFixed(1);
      const sac = path && path.sac !== null ? path.sac : null, wall = path && path.wall !== null ? path.wall : null;
      return `<div class="nl-hd">${esc(T('ndl_title', 'NEEDLE PATH'))}</div>
        <svg class="nl" viewBox="0 0 76 ${h + 8}">
          <rect class="trk" x="30" y="4" width="10" height="${h}" rx="3"/>
          ${sac !== null && wall !== null ? `<rect class="sac" x="27" y="${(+y(sac) + 4).toFixed(1)}" width="16" height="${Math.max(2, +y(wall) - +y(sac)).toFixed(1)}" rx="2"/>` : ''}
          ${wall !== null ? `<rect class="wall" x="27" y="${(+y(wall) + 4).toFixed(1)}" width="16" height="${(h - +y(wall)).toFixed(1)}" rx="2"/>` : ''}
          ${[0, 2, 4, 6, 8, 10, 12].map(c => `<line class="tk" x1="22" x2="27" y1="${(+y(c) + 4).toFixed(1)}" y2="${(+y(c) + 4).toFixed(1)}"/><text class="tt" x="19" y="${(+y(c) + 7).toFixed(1)}">${c}</text>`).join('')}
          <path class="tip" d="M46 ${(+y(S.depth) + 4).toFixed(1)} l9 -6 v12 z"/>
          <line class="sh" x1="35" y1="4" x2="35" y2="${(+y(S.depth) + 4).toFixed(1)}"/>
        </svg>
        <div class="nl-r"><span>${esc(T('ndl_tip', 'tip'))}</span><b>${S.depth.toFixed(1)}</b></div>
        <div class="nl-r sac"><span>${esc(T('ndl_sac', 'sac'))}</span><b>${sac !== null ? sac.toFixed(1) : '--'}</b></div>
        <div class="nl-r wall"><span>${esc(T('ndl_wall', 'heart'))}</span><b>${wall !== null ? wall.toFixed(1) : '--'}</b></div>`;
    }

    function finish() {
      if (S.done) return;
      S.done = true;
      let score = 100 - S.touches * 18 - Math.max(0, S.t - 70) * 0.25;
      const resid = Math.max(0, S.ml - S.leftOver) / ml0;
      score -= resid * 60;
      score = clamp(Math.round(score), 0, 100);
      pp.set({ title: T('reading_peri', 'Checking the result…'), text: '', tools: [] });
      NZA.post('ultrasound:finish', { result: { score, drawn: Math.round(S.drawn), touches: S.touches, passes: S.passes, left: Math.round(S.ml) } }).then(r => {
        if (r && r.outcome) api.msg.result(r.outcome);
      });
    }

    function frame(dt, now) {
      S.t += dt;
      const A = app.anchors();
      if (S.phase === 'window' && S.mouse && !S.done) {
        const t = UI.screenToTorso(S.mouse, A);
        if (t && t.inside) { S.tgt.x = t.x; S.tgt.y = t.y; S.p.contact = true; } else S.p.contact = false;
        const k = 1 - Math.exp(-dt * 14);
        S.p.x = lerp(S.p.x, S.tgt.x, k); S.p.y = lerp(S.p.y, S.tgt.y, k);
      }
      const v = UI.probeView(S.p.x, S.p.y, 90, 20);
      const isHeart = v.win.id === 'cardiac';
      const q = S.p.contact && isHeart ? v.q : S.p.contact ? 0.1 : 0;
      if (S.phase === 'window') S.hold = q >= 0.7 ? S.hold + dt : Math.max(0, S.hold - dt * 2);
      // needle
      S.ang = lerp(S.ang, S.angT, 1 - Math.exp(-dt * 10));
      if (S.phase === 'needle' || S.phase === 'draw' || S.phase === 'out') {
        const was = S.depth;
        if (S.lmb && S.phase !== 'out') S.depth = clamp(S.depth + dt * 1.25, 0, 13);
        if (S.rmb) S.depth = clamp(S.depth - dt * 1.7, 0, 13);
        if (S.depth > 0.4 && was <= 0.4) S.passes++;
        dev.state.needle = { on: S.depth > 0.05, guide: true, ex: -6.6, ez: 0, ang: S.ang, depth: S.depth, inPlane: 1 };
        dev.engine.set({ needle: dev.state.needle });
      }
      // the sac drains while drawing
      const path = (S.phase !== 'window') ? dev.engine.needlePath() : null;
      const hit = path ? path.hit : null;
      if (S.phase !== 'window') {
        if (hit === 'heart') {
          if (!S.inHeart) {
            S.inHeart = true; S.touches++;
            dev.ectopic();
            NZA.audio.tone(220, 160, { vol: 0.12, type: 'square' });
            pp.flash('bad', T('pc_fl_heart', 'Heart wall! Pull back now ({RMB}).'), 2600);
            pp.stat('touch', { value: String(S.touches), tone: 'red' });
            app.post('needle', { touch: true });
          }
        } else S.inHeart = false;
        if (hit === 'sac' && !S.wasIn) { S.wasIn = true; S.flash = 1; NZA.audio.tone(660, 70, { vol: 0.06 }); if (S.phase === 'needle') setPhase('draw'); }
        if (S.f && hit === 'sac' && S.syr < S.syrMax && S.ml > 0) {
          const take = Math.min(S.rate * dt, S.syrMax - S.syr, S.ml);
          S.syr += take; S.drawn += take; S.ml -= take;
          if (S.syr >= S.syrMax - 0.5) { pp.flash('warn', T('pc_fl_full', 'Syringe full. Press {T} to empty it, keep the needle still.'), 3000); }
        } else if (S.f && hit !== 'sac' && S.phase === 'draw') {
          S.fWarnT = (S.fWarnT || 0) + dt;
          if (S.fWarnT > 1.2) { S.fWarnT = 0; pp.flash('warn', T('pc_fl_dry', 'Nothing comes back: the tip is out of the black band.'), 2200); }
        }
        if (S.phase === 'draw' && S.ml <= S.leftOver) setPhase('out');
        if (S.phase === 'out' && S.depth <= 0.02) finish();
      }
      // effusion thickness follows what is left
      S.mmNow = Math.max(1.5, (d.mm || 12) * Math.pow(S.ml / ml0, 0.8));
      dev.engine.set({ effusion: S.mmNow });
      // simulated recovery while the sac empties (display only; the server applies the real change)
      const rec = clamp(1 - S.ml / ml0, 0, 1);
      dev.vitals(Object.assign({}, S.vit, { hr: Math.round(S.hr0 - (S.hr0 - 92) * rec), sys: Math.round(S.sys0 + (112 - S.sys0) * rec) }));
      dev.set({ contact: S.p.contact, flip: false, engine: { scene, contact: S.p.contact, q, shift: isHeart ? v.shift : 0, vis: isHeart ? v.vis : 0.4, tilt: 20 } });
      S.acc += dt;
      if (S.acc >= 0.045) { const fdt = Math.min(S.acc, 0.1); S.acc = 0; dev.frame(fdt, now); }
      if (S.phase === 'window') dev.window('cardiac', q, UI.wName('cardiac'));
      if (S.mouse && S.phase === 'window') {
        const z = NZA.zoom || 1;
        reticle.style.left = `${(S.mouse.cx / z).toFixed(1)}px`; reticle.style.top = `${(S.mouse.cy / z).toFixed(1)}px`;
        reticle.classList.toggle('on', S.p.contact); reticle.classList.toggle('good', q >= 0.7);
        reticle.querySelector('.fp').setAttribute('transform', 'rotate(-180)');
        reticle.querySelector('.lb').textContent = S.hold > 0.8 ? 'F' : '';
      } else reticle.classList.remove('on');
      // syringe widget
      S.flash = Math.max(0, S.flash - dt * 0.6);
      const fillW = S.syr / S.syrMax * 186;
      syr.querySelector('.bl').setAttribute('width', fillW.toFixed(1));
      syr.querySelector('.pl').setAttribute('x', (56 + fillW).toFixed(1));
      syr.querySelector('.rod').setAttribute('x', (66 + fillW).toFixed(1));
      syr.querySelector('.thumb').setAttribute('x', (250 + fillW * 0.0).toFixed(1));
      syr.querySelector('.fl').style.opacity = String(Math.max(S.flash, hit === 'sac' ? 0.85 : 0));
      syr.querySelector('.sy-v').innerHTML = `${Math.round(S.syr)}<em> / ${S.syrMax} mL</em>`;
      syr.querySelector('.sy-sac').textContent = `~${Math.round(S.ml)} mL`;
      syr.classList.toggle('drawing', S.f && hit === 'sac');
      S.uiT += dt;
      if (S.uiT > 0.1) {
        S.uiT = 0;
        dev.ndl(S.phase === 'window' ? '' : ndlHTML(path));
        const frac = S.ml / ml0;
        pp.wide({ value: String(Math.round(S.ml)), meter: { value: frac, zone: [0, S.leftOver / ml0], tone: frac > 0.5 ? 'red' : frac > S.leftOver / ml0 ? 'amber' : '' } });
        pp.stat('tip', { value: S.depth.toFixed(1), tone: hit === 'sac' ? 'teal' : hit === 'heart' ? 'red' : '' });
        pp.stat('drawn', { value: String(Math.round(S.drawn)), tone: S.drawn > 0 ? 'teal' : '' });
        dev.flag(hit === 'sac' ? T('pc_flag_sac', 'TIP IN THE SAC') : hit === 'heart' ? T('pc_flag_heart', 'TIP ON THE HEART') : '', hit === 'heart' ? 'red' : 'teal');
        refreshTools();
      }
      S.sendT += dt;
      if (S.sendT > 0.1) {
        S.sendT = 0;
        if (S.phase === 'window') NZA.post('ultrasound:probe', { x: +S.p.x.toFixed(3), y: +S.p.y.toFixed(3), rot: 90, tilt: 20, contact: S.p.contact });
        else app.post('needle', { depth: +S.depth.toFixed(2), ang: +S.ang.toFixed(2), draw: !!S.f });
      }
    }

    const api = {
      key(e) {
        if (S.done) { if (e.key === 'Enter') { pp.key(e); return true; } return false; }
        if (e.code === 'KeyF') { if (S.phase === 'window') pressF(); else { S.f = true; refreshTools(); } return true; }
        if (e.code === 'KeyT') { empty(); return true; }
        return false;
      },
      keyUp(e) { if (e.code === 'KeyF') { S.f = false; refreshTools(); return true; } return false; },
      frame,
      msg: {
        vitals(v) { S.vit = Object.assign(S.vit, v || {}); },
        result(o) {
          S.done = true;
          const good = !o.failed && !o.vf;
          dev.flag(o.vf ? T('pc_res_vf', 'VF — start CPR') : good ? T('pc_res_ok', 'SAC DRAINED') : T('pc_res_none', 'NOTHING DRAWN'), good ? 'teal' : 'red');
          pp.complete({
            title: o.vf ? T('pc_res_vf_t', 'The heart went into VF') : T('pc_res_t', 'Drained · %s', o.grade || '-'),
            text: o.msg || '', label: T('done', 'Done'), onDone: () => app.close(),
          });
          pp.wide({ label: T('score', 'Score'), value: String(o.score ?? 0), unit: '', meter: { value: (o.score || 0) / 100, zone: [0.72, 1] }, caption: T('grade', 'grade %s', o.grade || '-'), captionTone: good ? 'teal' : 'red' });
          NZA.audio[good ? 'success' : 'fail']();
        },
      },
      destroy() {
        app.el.removeEventListener('mousemove', onMove);
        app.el.removeEventListener('mousedown', onDown);
        window.removeEventListener('mouseup', onUp);
        pp.destroy(); dev.destroy(); ppHost.remove(); reticle.remove();
      },
    };
    setPhase('window');
    return api;
  }

  U.modes = Object.assign(U.modes || {}, { scan: ScanMode, pericardio: PeriMode });
})();

/* ═══════════════════════════════════════════════════════════
   Part 5 · the NUI app: mode router, frame loop, Lua bridge, preview

   Lua → JS   open { mode = 'scan'|'pericardio'|'chestdrain'|'decompress', locale, keys, inv, perms,
                     stepItems, …server data (views, seed, study, patient, vitals, plan, drains, labels,
                     minSeen | ml, mm, syringe, drawRate, leftOver | side, haemo, ptx, tension, numbing) }
              anchors (core: torso grid g<i>_<j>)   vitals { hr, rhythm, sys, dia, spo2, rr }
              result (server outcome)               abort ()            launchFailed { msg }
   JS → Lua   ultrasound:probe { x, y, rot, tilt, contact }      ultrasound:needle { depth, ang, draw, touch, phase }
              ultrasound:finish { result } → { ok, outcome? }     ultrasound:launch { action, side, result } → { ok, msg? }
              ultrasound:flinch { pain }    ultrasound:abort {}   ultrasound:close (core)
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA || !window.NZA.app || !window.NZUS || !window.NZUS.ui) return;
  const U = window.NZUS, UI = U.ui;
  const T = (...a) => UI.T(...a);
  const esc = NZA.esc;
  const KEYS = [' ', 'Enter', 'KeyC', 'KeyM', 'KeyP', 'KeyN', 'KeyQ', 'KeyE', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'KeyF', 'KeyT', 'KeyX', 'KeyR', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

  const app = NZA.app('ultrasound', {
    escClose: false, full: true, noscale: true, camInput: true,

    init(el) {
      this.root = el;
      el.innerHTML = `<div class="us-stage"></div><div class="us-ui"></div>
        <div class="us-load"><div class="in"><span class="ring"></span><span class="lt"></span></div></div>`;
      this.stage = el.querySelector('.us-stage');
      this.uiEl = el.querySelector('.us-ui');
      this.loadEl = el.querySelector('.us-load');
      this.keys = {};
      this.keysUp = {};
      KEYS.forEach(k => {
        this.keys[k] = e => (this.mode && this.mode.key ? this.mode.key(e) : false);
      });
      this.keysUp.KeyF = e => (this.mode && this.mode.keyUp ? this.mode.keyUp(e) : false);
      this.keysUp[' '] = e => (this.mode && this.mode.keyUp ? this.mode.keyUp(e) : false);
      this.keysUp.KeyX = e => (this.mode && this.mode.keyUp ? this.mode.keyUp(e) : false);
      this.anc = NZA.ui.Anchors('ultrasound');
    },

    open(d) {
      this.teardown();
      UI.setLocale(Object.assign({}, d.locale || {}));
      this.d = d;
      const mode = d.mode || 'scan';
      this.modeName = mode;
      this.camInput = mode === 'scan';
      this.alive = true;
      this.root.classList.toggle('us-3d', mode === 'chestdrain' || mode === 'decompress');
      this.root.classList.add('us-m-' + mode);
      const Mode = U.modes && U.modes[mode];
      if (!Mode) { console.error('[ultrasound] unknown mode', mode); return; }
      const ctx = this.ctx();
      const boot = () => {
        if (!this.alive) return;
        try { this.mode = Mode(ctx, d); } catch (e) { console.error('[ultrasound] mode', e); this.mode = null; }
        this.loadEl.classList.add('out');
        this.last = performance.now();
        const loop = now => {
          if (!this.alive) return;
          const dt = Math.min(0.1, Math.max(0.001, (now - this.last) / 1000));
          this.last = now;
          if (this.mode && this.mode.frame) { try { this.mode.frame(dt, now); } catch (e) { console.error('[ultrasound] frame', e); } }
          this.raf = requestAnimationFrame(loop);
        };
        this.raf = requestAnimationFrame(loop);
      };
      if (this.root.classList.contains('us-3d')) {
        this.loadEl.classList.remove('out');
        this.loadEl.querySelector('.lt').textContent = T('loading', 'Preparing the field…');
        requestAnimationFrame(() => requestAnimationFrame(boot));
      } else { this.loadEl.classList.add('out'); boot(); }
    },
    close() { this.teardown(); },

    teardown() {
      this.alive = false;
      cancelAnimationFrame(this.raf);
      if (this.mode && this.mode.destroy) { try { this.mode.destroy(); } catch (e) { console.error('[ultrasound] destroy', e); } }
      this.mode = null;
      if (this.uiEl) this.uiEl.innerHTML = '';
      if (this.stage) this.stage.innerHTML = '';
      if (this.root) this.root.className = this.root.className.split(' ').filter(c => !c.startsWith('us-m-') && c !== 'us-3d').join(' ');
    },

    ctx() {
      const self = this;
      return {
        el: this.root, ui: this.uiEl, stage: this.stage,
        anchors: () => (self.previewAnchors ? self.previewAnchors() : self.anc.all()),
        post: (ev, data) => NZA.post(`ultrasound:${ev}`, data || {}),
        close: () => { self.teardown(); NZA.close('ultrasound'); },
        abort: () => { NZA.post('ultrasound:abort', {}); self.teardown(); NZA.closeLocal('ultrasound'); if (!NZA.inGame) self.preview(); },
      };
    },

    msg: {
      vitals(v) { const a = NZA.apps.ultrasound; if (a.mode && a.mode.msg && a.mode.msg.vitals) a.mode.msg.vitals(v); },
      result(o) { const a = NZA.apps.ultrasound; if (a.mode && a.mode.msg && a.mode.msg.result) a.mode.msg.result(o || {}); },
      launchFailed(r) { const a = NZA.apps.ultrasound; if (a.mode && a.mode.msg && a.mode.msg.launchFailed) a.mode.msg.launchFailed(r || {}); },
      abort() { const a = NZA.apps.ultrasound; a.teardown(); NZA.closeLocal('ultrasound'); },
    },

    /* ═════════════ browser preview ═════════════ */
    preview() {
      const mode = new URLSearchParams(location.search).get('mode') || 'scan';
      const inv = {
        chest_drain_kit: { label: 'Chest Drain Kit', count: 1 }, decomp_needle: { label: 'Decompression Needle', count: 2 },
        iv_kit: { label: 'IV Kit', count: 3 }, tourniquet: { label: 'Tourniquet', count: 1 }, bandage: { label: 'Bandage', count: 4 },
        gauze: { label: 'Gauze', count: 0 }, surgical_kit: { label: 'Surgical Kit', count: 0 }, angio_kit: { label: 'Angio Kit', count: 1 },
        contrast: { label: 'Contrast Dye', count: 2 }, coil: { label: 'Embolization Coil', count: 1 }, lidocaine: { label: 'Lidocaine 2%', count: 2 },
      };
      const base = {
        mode, inv, perms: { chestdrain: true, pericardio: true, decompress: true },
        stepItems: { chestdrain: { chest_drain_kit: 1 }, decompress: { decomp_needle: 1 }, pericardio: { iv_kit: 1 }, angio: { angio_kit: 1, contrast: 1, coil: 1 } },
        locale: { rg_r_upper_leg: 'right thigh', rg_chest: 'chest', rg_abdomen: 'abdomen' },
        seed: 4512, study: 'US-04512', patient: { name: 'Michael Garcia', sex: 'm', age: 34 },
        vitals: { hr: 118, ecgRate: 118, rhythm: 'stach', sys: 84, dia: 52, spo2: 91, rr: 26 },
      };
      const demo = {
        scan: { views: { ruq: { pleural: 45, free: 9 }, luq: {}, pelvis: { free: 11 }, cardiac: { effusion: 14, collapse: true }, lung_r: { slide: true }, lung_l: { ptx: true, size: 30 } },
          plan: [{ id: 'bleeding', kind: 'bleeding', regions: ['r_upper_leg'], items: { tourniquet: 1 }, order: 10 }, { id: 'fragments', kind: 'fragments', regions: ['chest'], items: { surgical_kit: 1 }, order: 90 }],
          drains: { left: false, right: false }, labels: true, minSeen: 1.2 },
        pericardio: { ml: 210, rate: 9, syringe: 60, drawRate: 7, leftOver: 20, mm: 15, views: { cardiac: { effusion: 15, collapse: true } }, labels: true },
        chestdrain: { side: 'right', haemo: 1100, haemoRate: 14, ptx: 25, tension: false, numbing: true, quality: 'high' },
        decompress: { side: 'left' },
      };
      const data = Object.assign({}, base, demo[mode] || demo.scan);
      NZA.mock('ultrasound:finish', r => new Promise(res => setTimeout(() => {
        const R = (r && r.result) || {};
        if (mode === 'scan') {
          const truth = { ruq: true, luq: false, pelvis: true, cardiac: true, lung_r: false, lung_l: true };
          const W = {}, missed = [];
          let pts = 0;
          Object.keys(truth).forEach(w => {
            const m = R.marks && R.marks[w];
            let result;
            if (!m) { result = truth[w] ? 'missed' : 'skipped'; if (truth[w]) missed.push(w); } else if ((m === 'pos') === truth[w]) { result = 'correct'; pts++; } else { result = m === 'neg' ? 'missed' : 'false'; if (m === 'neg') missed.push(w); }
            W[w] = { pos: truth[w], result, mark: m };
          });
          const score = Math.round(pts / 6 * 100);
          res({ ok: true, outcome: { score, grade: score >= 85 ? 'A' : score >= 72 ? 'B' : score >= 58 ? 'C' : 'D', windows: W, missed,
            plan: [{ id: 'bleeding', kind: 'bleeding', regions: ['r_upper_leg'], items: { tourniquet: 1 } }, { id: 'drain_right', kind: 'chestdrain', side: 'right', cause: 'haemothorax', items: { chest_drain_kit: 1 }, action: 'chestdrain' },
              { id: 'drain_left', kind: 'chestdrain', side: 'left', cause: 'pneumothorax', items: { chest_drain_kit: 1 }, action: 'chestdrain' }, { id: 'pericardio', kind: 'pericardio', items: { iv_kit: 1 }, action: 'pericardio' },
              { id: 'angio', kind: 'angio', items: { angio_kit: 1, contrast: 1, coil: 1 } }, { id: 'fragments', kind: 'fragments', regions: ['chest'], items: { surgical_kit: 1 } }],
            msg: missed.length ? `${missed.length} problem(s) missed on the scan.` : 'Every problem found.' } });
        } else if (mode === 'pericardio') res({ ok: true, outcome: { score: R.score || 80, grade: 'A', drawn: R.drawn || 0, msg: `${R.drawn || 0} mL drawn off. The heart fills again.` } });
        else res({ ok: true, outcome: { score: R.score || 84, grade: 'A', drained: 940, msg: mode === 'decompress' ? 'Hiss of air. The trapped air is out.' : '940 mL drained. The lung is opening up.' } });
      }, 600)));
      NZA.mock('ultrasound:launch', { ok: true });
      NZA.mock('ultrasound:probe', { ok: true });
      NZA.mock('ultrasound:needle', { ok: true });
      NZA.mock('ultrasound:abort', { ok: true });
      NZA.mock('ultrasound:flinch', { ok: true });
      if (mode === 'scan' || mode === 'pericardio') this.previewWorld();
      NZA.demo('ultrasound', data);
    },

    // a stand-in patient for the browser preview: lit torso on a trolley, anchors projected from it
    previewWorld() {
      const THREE = window.THREE;
      if (!THREE || this.pw) return;
      const cv = document.createElement('canvas');
      cv.className = 'us-pw';
      document.body.prepend(cv);
      const bg = document.querySelector('.nza-bg');
      if (bg) bg.remove();
      const r = new THREE.WebGLRenderer({ canvas: cv, antialias: true });
      r.setPixelRatio(1);
      r.outputEncoding = THREE.sRGBEncoding;
      r.toneMapping = THREE.ACESFilmicToneMapping;
      r.toneMappingExposure = 1.05;
      r.shadowMap.enabled = true;
      const sc = new THREE.Scene();
      sc.background = new THREE.Color(0x1b2024);
      sc.fog = new THREE.Fog(0x1b2024, 2.2, 4.5);
      const cam = new THREE.PerspectiveCamera(46, 16 / 9, 0.05, 20);
      const size = () => { r.setSize(window.innerWidth, window.innerHeight, false); cam.aspect = window.innerWidth / window.innerHeight; cam.updateProjectionMatrix(); };
      size();
      window.addEventListener('resize', size);
      sc.add(new THREE.HemisphereLight(0xdfe8ee, 0x2a2420, 0.55));
      const key = new THREE.SpotLight(0xfff1e2, 1.6, 0, 0.55, 0.6, 1);
      key.position.set(0.35, 1.9, 0.25); key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0005;
      sc.add(key); sc.add(key.target);
      // trolley mattress + sheet
      const mat = new THREE.Mesh(new THREE.BoxGeometry(0.78, 0.12, 2.1), new THREE.MeshStandardMaterial({ color: 0x3c4a54, roughness: 0.9 }));
      mat.position.set(0, -0.17, 0.05); mat.receiveShadow = true; sc.add(mat);
      const sheet = new THREE.Mesh(new THREE.PlaneGeometry(0.74, 2.0, 1, 1), new THREE.MeshStandardMaterial({ color: 0xc9d6dc, roughness: 0.95 }));
      sheet.rotation.x = -Math.PI / 2; sheet.position.set(0, -0.108, 0.05); sheet.receiveShadow = true; sc.add(sheet);
      const floor = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), new THREE.MeshStandardMaterial({ color: 0x23292d, roughness: 1 }));
      floor.rotation.x = -Math.PI / 2; floor.position.y = -0.95; sc.add(floor);
      // torso (same parameterisation as the probe view)
      const prof = [[0.0, -0.36], [0.16, -0.35], [0.2, -0.27], [0.18, -0.12], [0.165, 0.0], [0.178, 0.12], [0.205, 0.24], [0.215, 0.3], [0.17, 0.35], [0.06, 0.38], [0.0, 0.385]].map(p => new THREE.Vector2(p[0], p[1]));
      const lg = new THREE.LatheGeometry(prof, 64);
      lg.rotateX(Math.PI / 2); lg.scale(1, 0.58, 1);
      const skin = new THREE.MeshStandardMaterial({ color: 0xb98466, roughness: 0.55, metalness: 0.0 });
      const torso = new THREE.Mesh(lg, skin);
      torso.castShadow = true; torso.receiveShadow = true;
      sc.add(torso);
      // shorts + neck + arms (simple forms)
      const shorts = new THREE.Mesh(new THREE.CylinderGeometry(0.205, 0.2, 0.2, 40, 1, true), new THREE.MeshStandardMaterial({ color: 0x1d2329, roughness: 0.9, side: THREE.DoubleSide }));
      shorts.rotation.x = Math.PI / 2; shorts.scale.set(1, 1, 0.62); shorts.position.set(0, 0, -0.38); sc.add(shorts);
      const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.07, 0.12, 20), skin);
      neck.rotation.x = Math.PI / 2; neck.position.set(0, 0.02, 0.43); sc.add(neck);
      [-1, 1].forEach(s => {
        const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.045, 0.42, 6, 14), skin);
        arm.rotation.x = Math.PI / 2; arm.rotation.z = s * 0.08; arm.position.set(s * 0.27, -0.03, 0.08); arm.castShadow = true; sc.add(arm);
      });
      // nipples / navel / sternum hints
      const dark = new THREE.MeshStandardMaterial({ color: 0x6e4434, roughness: 0.6 });
      [[-0.1, 0.24], [0.1, 0.24]].forEach(([x, z]) => { const n = new THREE.Mesh(new THREE.CircleGeometry(0.011, 16), dark); n.position.set(x, 0.108, z); n.rotation.x = -Math.PI / 2; sc.add(n); });
      const nav = new THREE.Mesh(new THREE.CircleGeometry(0.008, 16), new THREE.MeshStandardMaterial({ color: 0x4a2c22 })); nav.position.set(0, 0.097, -0.12); nav.rotation.x = -Math.PI / 2; sc.add(nav);
      // probe prop that follows the probe
      const probe = new THREE.Group();
      const pbody = new THREE.Mesh(new THREE.CapsuleGeometry(0.018, 0.09, 6, 16), new THREE.MeshStandardMaterial({ color: 0xe9eef0, roughness: 0.35 }));
      pbody.position.y = 0.075; pbody.scale.set(1.25, 1, 0.75); probe.add(pbody);
      const pcable = new THREE.Mesh(new THREE.CylinderGeometry(0.005, 0.005, 0.12, 8), new THREE.MeshStandardMaterial({ color: 0x2a2f33 }));
      pcable.position.y = 0.17; probe.add(pcable);
      probe.traverse(o => { if (o.isMesh) o.castShadow = true; });
      sc.add(probe);
      // the camera looks down from the feet so the head is at the top of the screen; the torso sits left of centre
      const camPos = new THREE.Vector3(-0.2, 0.97, -0.42), look = new THREE.Vector3(-0.2, 0, 0.05);
      cam.position.copy(camPos); cam.lookAt(look);
      key.target.position.set(0, 0, 0);
      const surf = (x, y) => {
        const z = THREE.MathUtils.lerp(-0.33, 0.33, y);
        const a = Math.max(-1.25, Math.min(1.25, x)) * 1.2;
        const rx = 0.19, ry = 0.112;
        return new THREE.Vector3(-Math.sin(a) * rx, Math.cos(a) * ry, z);
      };
      const anchors = () => {
        const out = {};
        UI.GX.forEach((gx, i) => UI.GY.forEach((gy, j) => {
          const p = surf(gx, gy).project(cam);
          out[`g${i}_${j}`] = { x: (p.x + 1) / 2, y: (1 - p.y) / 2, visible: p.z < 1 };
        }));
        return out;
      };
      this.previewAnchors = anchors;
      const tick = () => {
        const m = this.mode;
        // follow the probe the controller reports to Lua (preview: read it back from the mock post)
        const last = this._lastProbe;
        if (last && last.contact) {
          const p = surf(last.x, last.y);
          const n = new THREE.Vector3(-Math.sin(last.x * 1.2) / 0.19, Math.cos(last.x * 1.2) / 0.112, 0).normalize();
          probe.visible = true;
          probe.position.copy(p);
          probe.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), n);
          probe.rotateY(-(last.rot || 0) * Math.PI / 180);
        } else probe.visible = false;
        r.render(sc, cam);
        this.pwRaf = requestAnimationFrame(tick);
        return m;
      };
      const orig = NZA.post;
      NZA.post = (name, data) => { if (name === 'ultrasound:probe') this._lastProbe = data; return orig(name, data); };
      this.pw = { cv, r };
      tick();
    },
  });

  // keep camera input off while the pointer works the device panel / plan card
  document.addEventListener('mouseover', e => {
    const a = NZA.apps.ultrasound;
    if (!a || !a.mode || !a.mode.overUi) return;
    const over = !!(e.target && e.target.closest && e.target.closest('.us-dev,.us-plan,.pp-card,.pp-belt,.pp-read,.pp-bot'));
    a.mode.overUi(over);
  });

  void app; void esc;
})();
