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
        if (left) L.push({ k: 'spleen', x: ix(SPL.cx + 0.6), z: SPL.cz - 0.4 });
        else L.push({ k: 'liver', x: ix(2.2), z: 4.4 });
        L.push({ k: 'kidney', x: ix(K.kx + 0.4), z: K.kz });
        L.push({ k: 'diaphragm', x: ix(K.dcx - K.R) + 1.5, z: K.dcz - 1.6, small: true });
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
    cam.position.set(0.95, 0.9, -0.9); cam.lookAt(0, -0.03, 0.08);
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
    // head, neck and upper arms so the body reads at a glance
    const solid = new THREE.MeshStandardMaterial({ color: 0x223d3c, roughness: 0.6, emissive: 0x041816 });
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.1, 24, 16), solid); head.scale.set(0.85, 0.95, 1.1); head.position.set(0, 0.01, 0.5); scene.add(head);
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.06, 0.1, 16), solid); neck.rotation.x = Math.PI / 2; neck.position.set(0, 0.0, 0.39); scene.add(neck);
    [-1, 1].forEach(sg => { const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.04, 0.3, 4, 12), solid); arm.rotation.x = Math.PI / 2; arm.position.set(sg * 0.25, -0.02, 0.12); scene.add(arm); });
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
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.02, 12, 10), new THREE.MeshBasicMaterial({ color: 0xffffff }));
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
    try { trace = NZA.vitals && NZA.vitals.Trace ? NZA.vitals.Trace(ecgC, { type: 'ecg', rhythm: 'sinus', rate: 80, color: '#3ddc84', speed: 0.5, line: 1.5, gain: 0.34 }) : null; } catch (e) { trace = null; }
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
      liver: 'LIVER', spleen: 'SPLEEN', kidney: 'KIDNEY', diaphragm: 'DIAPHRAGM', pleural: 'PLEURAL FLUID', spine: 'SPINE',
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
   Part 4 · chest drain and needle decompression (full-screen 3D close-up, core/nza3d.js)

   Chest drain (side of the chest, head at the top of the screen, front of the body toward the
   screen edge on the drain side):
     1 Find the spot    tool 1 gloved hand: hold LMB and sweep, the ribs light up under the
                        fingers (palpation lens) and are counted; tool 2 skin marker: click the
                        5th rib space in the middle of the armpit line (ink X on the skin)
     2 Clean            tool 3 swab: hold LMB and scrub the antiseptic over the mark; the sterile
                        drape with its window then drops over the field
     3 Numb (optional)  tool 4 lidocaine: hold LMB on the mark until the bleb rises ({N} skips)
     4 Cut              tool 5 scalpel: press at one end of the guide and drag along the rib
     5 Through the wall tool 6 clamp: hold LMB in the cut until it pops through; {Space} opens the jaws
     6 Finger sweep     tool 7 finger: hold LMB and circle around the hole
     7 Feed the tube    tool 8 tube: hold LMB and drag toward the head; stop at 10–14 cm, {Enter} clamps it
     8 Connect          tool 9 drain: click — blood / air drains, the lung re-expands
   Decompression (front of the chest): 1 feel the collarbone and count down, mark the 2nd space
   under the middle of the collarbone · 2 push the needle in (hold LMB) until the air hisses out.
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA || !window.NZA.app || !window.NZUS || !window.NZUS.ui) return;
  const U = window.NZUS, UI = U.ui;
  const { clamp, lerp, smooth } = U;
  const T = (...a) => UI.T(...a);
  const esc = NZA.esc, icon = NZA.icon;
  const MM = 0.001;
  const ORD = n => T('ord_' + n, ['', '1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th', '9th', '10th', '11th', '12th'][n] || `${n}th`);

  /* ─────────── shared 3D shell ─────────── */
  function Shell(app, d, o) {
    const root = app.ui;
    const S0 = { S: null, mouse: { x: 0.5, y: 0.5, cx: -999, cy: -999 }, moved: false, lmb: false };
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'us-ov3');
    app.el.appendChild(svg);
    const cur = document.createElement('div');
    cur.className = 'us-cur';
    cur.innerHTML = '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>';
    app.el.appendChild(cur);
    // patient card (top-left)
    const card = document.createElement('section');
    card.className = 'us-pt nza-hud solid';
    root.appendChild(card);
    const ppHost = document.createElement('div');
    ppHost.className = 'us-pp';
    root.appendChild(ppHost);
    let S = null;
    try {
      if (!window.NZA3D || !NZA3D.supported()) throw new Error('no webgl');
      S = NZA3D.createScene(app.stage, Object.assign({ tone: d.tone !== undefined ? +d.tone : 0.35, sex: (d.patient && d.patient.sex) || 'm', seed: (d.seed || 4512) >>> 0, quality: d.quality || 'high' }, o.scene || {}));
    } catch (e) { console.warn('[ultrasound] 3D unavailable', e); S = null; }
    S0.S = S;
    if (S) S.start();
    const onMove = e => { S0.moved = true; S0.mouse = { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight, cx: e.clientX, cy: e.clientY }; };
    window.addEventListener('mousemove', onMove);
    const api = {
      S, svg, cur, card, ppHost, state: S0,
      hit() { return S && S0.moved ? S.raycast(S.pointer) : null; },
      project(uv) { if (!S) return null; const p = S.project(uv); return { x: p.x * window.innerWidth, y: p.y * window.innerHeight, visible: p.visible !== false }; },
      ring(p, text, tone) {
        // p 0..1 → progress ring at the pointer, text chip beside it
        const C = 2 * Math.PI * 19;
        const on = S0.moved && p !== null && p !== undefined;
        cur.style.left = `${S0.mouse.cx.toFixed(1)}px`; cur.style.top = `${S0.mouse.cy.toFixed(1)}px`;
        cur.className = `us-cur ${on ? 'on' : ''} ${tone || ''}`;
        cur.querySelector('.fg').setAttribute('stroke-dasharray', `${(C * clamp(p || 0, 0, 1)).toFixed(1)} ${C.toFixed(1)}`);
        const tx = cur.querySelector('.tx');
        tx.textContent = text || ''; tx.className = `tx ${tone || ''}`;
      },
      patient(rows) {
        const p = d.patient || {};
        card.innerHTML = `<div class="hd"><span class="av">${icon('lungs')}</span><div><div class="nm">${esc(p.name || T('patient', 'Patient'))}</div><div class="sb">${esc(o.sub || '')}</div></div></div>
          <div class="rows">${rows.map(r => `<div class="rw" data-id="${esc(r.id || '')}"><span>${esc(r.label)}</span><b class="${r.tone || ''}">${esc(r.value)}</b></div>`).join('')}</div>`;
      },
      row(id, value, tone) {
        const b = card.querySelector(`.rw[data-id="${id}"] b`);
        if (b) { b.textContent = value; b.className = tone || ''; }
      },
      destroy() {
        window.removeEventListener('mousemove', onMove);
        if (S) { try { S.dispose(); } catch (e) { console.error('[ultrasound] dispose', e); } }
        svg.remove(); cur.remove(); card.remove(); ppHost.remove();
      },
    };
    return api;
  }

  // a hold-to-progress fallback when WebGL is missing (keeps the procedure playable, lower score)
  function Fallback(app, d, steps, title, extra) {
    const sh = Shell(app, d, { sub: title });
    let i = 0, prog = 0, hold = false, done = false;
    const pp = NZA.ui.ProcPanel(sh.ppHost, {
      tag: title, step: 1, total: steps.length, steps, title: steps[0], text: T('fb_text', 'No 3D view on this PC. Hold {Space} to do each step.'),
      wide: { label: T('fb_prog', 'Step'), value: '0', unit: '%', meter: { value: 0 } }, abort: { label: T('hold_stop_needle', 'Hold to stop'), key: 'ESC' }, onAbort: () => app.abort(),
    });
    sh.patient([]);
    const api = {
      key(e) { if (e.key === ' ') { hold = true; return true; } if (e.key === 'Enter' && done) { pp.key(e); return true; } return false; },
      keyUp(e) { if (e.key === ' ') { hold = false; return true; } return false; },
      frame(dt) {
        if (done) return;
        if (hold) prog += dt / 2.2;
        if (prog >= 1) {
          prog = 0; i++;
          if (i >= steps.length) {
            done = true;
            app.post('finish', { result: Object.assign({ score: 55 }, extra || {}) }).then(r => { if (r && r.outcome) api.msg.result(r.outcome); });
            return;
          }
          pp.set({ step: i + 1, title: steps[i] }); NZA.audio.success();
        }
        pp.wide({ value: String(Math.round(prog * 100)), meter: { value: prog } });
      },
      msg: { result(o) { pp.complete({ title: T('done_t', 'Done · %s', o.grade || '-'), text: o.msg || '', label: T('done', 'Done'), onDone: () => app.close() }); } },
      destroy() { pp.destroy(); sh.destroy(); },
    };
    return api;
  }

  /* ─────────── canvas helpers (glove grain, drape weave) ─────────── */
  function cv(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  // height canvas → tangent-space normal map canvas
  function heightToNormal(hc, strength) {
    const w = hc.width, h = hc.height, src = hc.getContext('2d').getImageData(0, 0, w, h).data;
    const out = cv(w, h), oc = out.getContext('2d'), id = oc.createImageData(w, h);
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
  const TEXCACHE = {};
  function gloveGrain() {
    if (TEXCACHE.glove) return TEXCACHE.glove;
    const n = 256, c = cv(n, n), x = c.getContext('2d'), r = U.rng(91);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < 5200; i++) { const v = 100 + r() * 70; x.fillStyle = `rgb(${v},${v},${v})`; x.beginPath(); x.arc(r() * n, r() * n, 0.6 + r() * 1.1, 0, Math.PI * 2); x.fill(); }
    // fine stretch lines along the fingers
    x.globalAlpha = 0.18;
    for (let i = 0; i < 90; i++) { const yy = r() * n; x.strokeStyle = r() < 0.5 ? '#5a5a5a' : '#a8a8a8'; x.lineWidth = 0.6; x.beginPath(); x.moveTo(0, yy); x.bezierCurveTo(n * 0.3, yy + r() * 6 - 3, n * 0.7, yy + r() * 6 - 3, n, yy); x.stroke(); }
    TEXCACHE.glove = heightToNormal(c, 2.2);
    return TEXCACHE.glove;
  }
  function weave() {
    if (TEXCACHE.weave) return TEXCACHE.weave;
    const n = 256, h = cv(n, n), x = h.getContext('2d'), r = U.rng(17);
    const a = cv(n, n), ax = a.getContext('2d');
    x.fillStyle = '#7a7a7a'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#c9c9c9'; ax.fillRect(0, 0, n, n);
    const th = 16, step = n / th;
    for (let i = 0; i < th; i++) {
      for (let j = 0; j < th; j++) {
        const over = (i + j) % 2 === 0;
        const px = i * step, py = j * step;
        const g = x.createLinearGradient(px, py, over ? px : px + step, over ? py + step : py);
        g.addColorStop(0, '#5c5c5c'); g.addColorStop(0.5, over ? '#d8d8d8' : '#b8b8b8'); g.addColorStop(1, '#5c5c5c');
        x.fillStyle = g; x.fillRect(px + 0.5, py + 0.5, step - 1, step - 1);
        const v = 190 + r() * 40;
        ax.fillStyle = `rgb(${v},${v},${v})`; ax.fillRect(px, py, step, step);
      }
    }
    ax.globalAlpha = 0.25;
    for (let i = 0; i < 260; i++) { const v = r() < 0.5 ? 150 : 235; ax.strokeStyle = `rgb(${v},${v},${v})`; ax.lineWidth = 0.7; ax.beginPath(); const sx = r() * n, sy = r() * n; ax.moveTo(sx, sy); ax.lineTo(sx + r() * 14 - 7, sy + r() * 14 - 7); ax.stroke(); }
    TEXCACHE.weave = { normal: heightToNormal(h, 3.0), albedo: a };
    return TEXCACHE.weave;
  }

  /* ─────────── custom meshes ─────────── */
  function meshes(S) {
    const THREE = window.THREE;
    const bin = [];
    const keep = x => { bin.push(x); return x; };
    const tex = (c, srgb) => { const t = keep(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 4; if (srgb) t.encoding = THREE.sRGBEncoding; return t; };
    const gloveN = tex(gloveGrain(), false); gloveN.repeat.set(3, 3);
    const M = {
      glove: keep(new THREE.MeshPhysicalMaterial({ color: new THREE.Color(0x2a49b8), roughness: 0.52, normalMap: gloveN, normalScale: new THREE.Vector2(0.3, 0.3), sheen: 0.4, sheenRoughness: 0.5, sheenColor: new THREE.Color(0x7f9cf0), clearcoat: 0.12, clearcoatRoughness: 0.5 })),
      cuff: keep(new THREE.MeshPhysicalMaterial({ color: new THREE.Color(0x2443a8), roughness: 0.5, sheen: 0.4, sheenColor: new THREE.Color(0x7f9cf0) })),
      sleeve: keep(new THREE.MeshStandardMaterial({ color: new THREE.Color(0x1b2533), roughness: 0.92 })),
      tube: keep(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.1, transparent: true, opacity: 0.38, clearcoat: 1, clearcoatRoughness: 0.05, depthWrite: false })),
      stripe: keep(new THREE.MeshStandardMaterial({ color: 0x1f5fd1, roughness: 0.4 })),
      blood: keep(new THREE.MeshPhysicalMaterial({ color: 0x5a0407, roughness: 0.22, clearcoat: 0.8, transparent: true, opacity: 0.93 })),
      mark: keep(new THREE.MeshBasicMaterial({ color: 0x15181a })),
      barrel: keep(new THREE.MeshPhysicalMaterial({ color: 0xf1f3f4, roughness: 0.34, clearcoat: 0.5, clearcoatRoughness: 0.3 })),
      ink: keep(new THREE.MeshPhysicalMaterial({ color: 0x5b2f9c, roughness: 0.35, clearcoat: 0.5 })),
      grip: keep(new THREE.MeshStandardMaterial({ color: 0x6a4bb8, roughness: 0.7 })),
      steel: keep(new THREE.MeshStandardMaterial({ color: 0xc9cfd4, roughness: 0.22, metalness: 1 })),
      connector: keep(new THREE.MeshPhysicalMaterial({ color: 0xe8edf1, roughness: 0.3, transparent: true, opacity: 0.85, clearcoat: 0.6 })),
      clampBlue: keep(new THREE.MeshStandardMaterial({ color: 0x2c63d6, roughness: 0.45 })),
    };
    // the medic's hand is drawn as an AR ghost (fresnel rim, soft fill, fades toward the wrist):
    // it shows exactly where the fingers press without hiding the skin under them
    const ghostU = { uTip: { value: new THREE.Vector3() }, uCol: { value: new THREE.Color(0x3ee8d8) }, uPress: { value: 0 } };
    M.ghost = keep(new THREE.ShaderMaterial({
      uniforms: ghostU, transparent: true, depthWrite: false, side: THREE.FrontSide, blending: THREE.NormalBlending,
      vertexShader: `varying vec3 vN; varying vec3 vV; varying vec3 vW;
        void main(){ vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; vec4 mv = viewMatrix * w; vV = -mv.xyz; vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform vec3 uTip; uniform vec3 uCol; uniform float uPress; varying vec3 vN; varying vec3 vV; varying vec3 vW;
        void main(){
          float f = 1.0 - abs(dot(normalize(vN), normalize(vV)));
          float rim = pow(f, 2.4);
          float d = distance(vW, uTip);
          float fade = 1.0 - smoothstep(0.09, 0.24, d);
          float near = 1.0 - smoothstep(0.0, 0.035, d);
          vec3 c = uCol * (0.35 + 1.5 * rim) + vec3(0.9, 1.0, 1.0) * near * (0.25 + 0.5 * uPress);
          float a = (0.1 + 0.62 * rim + near * (0.12 + 0.25 * uPress)) * fade;
          gl_FragColor = vec4(c, a);
        }`,
    }));
    M.ghost.depthFunc = THREE.LessEqualDepth;
    M.ghost.polygonOffset = true; M.ghost.polygonOffsetFactor = -1; M.ghost.polygonOffsetUnits = -4;
    M.depthOnly = keep(new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: true }));
    const V2 = (x, y) => new THREE.Vector2(x, y);
    // tapered capsule along -Y from 0 to -len (base radius r0, tip radius r1)
    function seg(len, r0, r1, flat) {
      const pts = [];
      for (let i = 8; i >= 0; i--) { const a = (i / 8) * Math.PI / 2; pts.push(V2(Math.max(1e-4, r1 * Math.cos(a)), -len - r1 * Math.sin(a))); }
      for (let i = 1; i <= 6; i++) { const t = i / 7; pts.push(V2(lerp(r1, r0, t), -len * (1 - t))); }
      for (let i = 0; i <= 8; i++) { const a = (i / 8) * Math.PI / 2; pts.push(V2(Math.max(1e-4, r0 * Math.cos(a)), r0 * 0.8 * Math.sin(a))); }
      const g = keep(new THREE.LatheGeometry(pts, 22));
      g.scale(flat || 1.08, 1, 0.9);
      return g;
    }
    // smooth palm: a squared-off ellipsoid (superellipse), narrower toward +Y (wrist), arched on the back
    function palmGeo(w, l, t, taper) {
      const g = keep(new THREE.SphereGeometry(1, 48, 32));
      const p = g.attributes.position;
      for (let i = 0; i < p.count; i++) {
        let x = p.getX(i), y = p.getY(i), zz = p.getZ(i);
        const sq = v => Math.sign(v) * Math.pow(Math.abs(v), 0.72);
        x = sq(x) * w / 2; y = sq(y) * l / 2; zz = sq(zz) * t / 2;
        const k = lerp(1, taper, clamp((y + l / 2) / l, 0, 1));
        x *= k;
        zz += (1 - Math.pow(x / (w / 2), 2)) * t * 0.12 * (zz > 0 ? 1 : 0.3);
        p.setXYZ(i, x, y, zz);
      }
      g.computeVertexNormals();
      return g;
    }

    /* gloved right hand + sleeve. Local frame = engine tool frame: origin at the contact point,
       +Y toward the wrist (tool axis), +Z back of the hand, palm toward -Z, thumb on +X. */
    function hand(pose) {
      const GM = M.ghost;
      const g = new THREE.Group();
      const inner = new THREE.Group();
      g.add(inner);
      const FINGERS = [
        { x: 0.026, len: [0.043, 0.025, 0.02], r: 0.0088, splay: -0.05 },   // index
        { x: 0.008, len: [0.047, 0.028, 0.021], r: 0.009, splay: 0.0 },    // middle
        { x: -0.011, len: [0.044, 0.026, 0.02], r: 0.0086, splay: 0.05 },  // ring
        { x: -0.028, len: [0.034, 0.02, 0.018], r: 0.0076, splay: 0.12 },  // little
      ];
      const P = {
        palpate: { flex: [[0.16, 0.14, 0.1], [0.18, 0.15, 0.1], [0.42, 0.5, 0.3], [0.5, 0.55, 0.32]], thumb: [0.5, 0.3, 0.25], tz: 0.42, tilt: 1.3, yaw: -0.32 },
        point: { flex: [[0.06, 0.05, 0.02], [1.35, 1.5, 0.8], [1.4, 1.55, 0.8], [1.45, 1.55, 0.8]], thumb: [0.9, 0.7, 0.6], tz: -0.25, tilt: 0.62, yaw: -0.9 },
      }[pose] || {};
      const pads = [];
      // palm
      const palm = new THREE.Mesh(palmGeo(0.08, 0.1, 0.026, 0.84), GM);
      palm.position.set(-0.001, 0.047, 0.0);
      palm.castShadow = true;
      inner.add(palm);
      FINGERS.forEach((f, fi) => {
        let parent = new THREE.Group();
        parent.position.set(f.x, 0.0, 0.0);
        parent.rotation.z = f.splay;
        inner.add(parent);
        const flex = P.flex[fi];
        f.len.forEach((L, si) => {
          const j = new THREE.Group();
          j.rotation.x = flex[si];
          parent.add(j);
          const r0 = f.r * (1 - si * 0.08), r1 = f.r * (0.9 - si * 0.08);
          const m = new THREE.Mesh(seg(L, r0, r1), GM);
          m.castShadow = true;
          j.add(m);
          const nx = new THREE.Group();
          nx.position.y = -L;
          j.add(nx);
          if (si === 2) { const pad = new THREE.Object3D(); pad.position.set(0, -L * 0.55, -r1 * 0.95); j.add(pad); pads[fi] = pad; }
          parent = nx;
        });
      });
      // thumb (from the palm's thumb side, palm-ward, pointing along the fingers)
      const tb = new THREE.Group();
      tb.position.set(0.04, 0.074, -0.008);
      tb.rotation.set(P.thumb[0] * 0.5, 0.35, P.tz);
      inner.add(tb);
      let tp = tb;
      [[0.04, 0.0118, 0.0108], [0.032, 0.0108, 0.0098]].forEach(([L, a, b], i) => {
        const j = new THREE.Group(); j.rotation.x = P.thumb[i + 1]; tp.add(j);
        const m = new THREE.Mesh(seg(L, a, b, 1.05), GM); m.castShadow = true; j.add(m);
        const nx = new THREE.Group(); nx.position.y = -L; j.add(nx); tp = nx;
      });
      // wrist, glove cuff, sleeve
      const wristG = keep(new THREE.CylinderGeometry(0.03, 0.033, 0.075, 28, 6, true));
      const wrist = new THREE.Mesh(wristG, GM); wrist.scale.set(1, 1, 0.72); wrist.position.set(-0.002, 0.13, 0.0); wrist.castShadow = true; inner.add(wrist);
      const cuff = new THREE.Mesh(keep(new THREE.TorusGeometry(0.035, 0.0035, 10, 36)), GM); cuff.rotation.x = Math.PI / 2; cuff.scale.set(1, 0.74, 1); cuff.position.set(-0.002, 0.167, 0); inner.add(cuff);
      // move the contact point (between the pads that touch) to the origin
      inner.updateMatrixWorld(true);
      const use = pose === 'point' ? [pads[0]] : [pads[0], pads[1]];
      const c = new THREE.Vector3();
      use.forEach(p => c.add(p.getWorldPosition(new THREE.Vector3())));
      c.multiplyScalar(1 / use.length);
      inner.position.sub(c);
      // depth pre-pass: only the outer surface of the ghost shows (no overlapping inner outlines)
      const ghosts = [];
      g.traverse(o2 => { if (o2.isMesh) ghosts.push(o2); });
      ghosts.forEach(o2 => {
        o2.castShadow = false; o2.renderOrder = 7;
        const dm = new THREE.Mesh(o2.geometry, M.depthOnly);
        dm.position.copy(o2.position); dm.quaternion.copy(o2.quaternion); dm.scale.copy(o2.scale);
        dm.renderOrder = 6;
        o2.parent.add(dm);
      });
      S.scene.add(g);
      g.visible = false;
      const tool = {
        group: g, name: 'hand_' + pose, press: 0, _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false,
        pose: { lift: 0.006, pressLift: pose === 'point' ? -0.016 : 0.0005, tilt: P.tilt, yaw: P.yaw, roll: 0, shadow: 0.05 },
        tipWorld: () => g.getWorldPosition(new THREE.Vector3()), set() {},
        update() { ghostU.uTip.value.copy(g.position); ghostU.uPress.value = tool.press; },
      };
      return tool;
    }

    // surgical skin marker: white barrel, violet grip and tip (tool frame: tip at origin, body +Y)
    function pen() {
      const g = new THREE.Group();
      const add = (geo2, mat, y) => { const m = new THREE.Mesh(keep(geo2), mat); m.position.y = y; m.castShadow = true; g.add(m); return m; };
      add(new THREE.ConeGeometry(0.0016, 0.006, 16), M.ink, 0.003).rotation.x = Math.PI;
      add(new THREE.CylinderGeometry(0.0034, 0.0016, 0.008, 20), M.barrel, 0.01);
      add(new THREE.CylinderGeometry(0.0052, 0.0044, 0.034, 24), M.grip, 0.031);
      add(new THREE.CylinderGeometry(0.0052, 0.0052, 0.07, 24), M.barrel, 0.083);
      add(new THREE.CylinderGeometry(0.0056, 0.0056, 0.026, 24), M.ink, 0.128);
      add(new THREE.SphereGeometry(0.0056, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), M.ink, 0.141);
      const clip = add(new THREE.BoxGeometry(0.0016, 0.03, 0.003), M.ink, 0.12); clip.position.x = 0.006;
      g.visible = false;
      S.scene.add(g);
      return {
        group: g, name: 'pen', press: 0, _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false,
        pose: { lift: 0.002, pressLift: 0.0, tilt: 0.62, yaw: 0.85, roll: 0.4, shadow: 0.012 },
        tipWorld: () => g.getWorldPosition(new THREE.Vector3()), set() {},
      };
    }

    // chest tube: clear PVC with a blue radio-opaque stripe, depth marks, the blood column inside,
    // a stepped connector and the clamp on the outside part
    function tube(curve) {
      const g = new THREE.Group();
      const outer = new THREE.Mesh(keep(new THREE.TubeGeometry(curve, 140, 0.0052, 20, false)), M.tube);
      outer.renderOrder = 3; g.add(outer);
      const stripeCurve = new THREE.CatmullRomCurve3(curve.getPoints(60).map((p, i, a) => {
        const t = curve.getTangentAt(Math.min(0.999, i / (a.length - 1)));
        const side = new THREE.Vector3(0, 1, 0).cross(t).normalize().multiplyScalar(0.0049);
        return p.clone().add(side);
      }));
      g.add(new THREE.Mesh(keep(new THREE.TubeGeometry(stripeCurve, 120, 0.0009, 6, false)), M.stripe));
      const inner = new THREE.Mesh(keep(new THREE.TubeGeometry(curve, 140, 0.0037, 12, false)), M.blood);
      inner.geometry.setDrawRange(0, 0);
      g.add(inner);
      const rings = [];
      for (let i = 0; i < 9; i++) {
        const r = new THREE.Mesh(keep(new THREE.TorusGeometry(0.0054, 0.0005, 6, 24)), M.mark);
        g.add(r); rings.push(r);
      }
      // connector at the far end + a roller clamp half way
      const end = curve.getPointAt(1), endT = curve.getTangentAt(1);
      const con = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.0062, 0.0075, 0.03, 20)), M.connector);
      con.position.copy(end).addScaledVector(endT, 0.012); con.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), endT); g.add(con);
      const cp = curve.getPointAt(0.62), ct = curve.getTangentAt(0.62);
      const cl = new THREE.Group();
      const body = new THREE.Mesh(keep(new THREE.BoxGeometry(0.02, 0.026, 0.009)), M.clampBlue); cl.add(body);
      const jaw = new THREE.Mesh(keep(new THREE.BoxGeometry(0.004, 0.028, 0.012)), M.clampBlue); jaw.position.x = 0.011; cl.add(jaw);
      cl.position.copy(cp); cl.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), ct);
      g.add(cl);
      g.traverse(c => { if (c.isMesh) c.castShadow = true; });
      S.scene.add(g);
      const total = inner.geometry.index ? inner.geometry.index.count : 0;
      return {
        g, curve, clamp: cl,
        // depth = cm fed in; marks every 2 cm from the tip slide toward the skin
        depth(cm) {
          const L = curve.getLength();
          rings.forEach((r, i) => {
            const fromTip = (i + 2) * 2;
            const outside = (fromTip - cm) / 100;
            if (outside < 0.002 || outside > L - 0.01) { r.visible = false; return; }
            r.visible = true;
            const t = outside / L;
            const p = curve.getPointAt(t), tg = curve.getTangentAt(t);
            r.position.copy(p);
            r.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), tg);
          });
        },
        fill(f) { inner.geometry.setDrawRange(0, Math.floor(total * clamp(f, 0, 1) / 6) * 6); },
        open(on) { cl.rotation.z = on ? 0.0 : 0.0; jaw.position.x = on ? 0.016 : 0.011; },
      };
    }

    /* fenestrated sterile drape with a round window at uv; drop(t 0..1) animates it settling */
    function drape(uv, radius) {
      const wv = weave();
      const nT = tex(wv.normal, false), aT = tex(wv.albedo, true);
      nT.repeat.set(1, 1); aT.repeat.set(1, 1);
      const c = S.uvToST(uv), W = S.patch.W, H = S.patch.H;
      const AS = 160, RS = 40, P = new THREE.Vector3(), N = new THREE.Vector3();
      const pos = new Float32Array((AS + 1) * (RS + 1) * 3), uvs = new Float32Array((AS + 1) * (RS + 1) * 2), base = new Float32Array((AS + 1) * (RS + 1) * 3), nrm = new Float32Array((AS + 1) * (RS + 1) * 3);
      const rr0 = U.rng(33);
      const folds = Array.from({ length: 8 }, () => ({ a: rr0() * Math.PI, f: 26 + rr0() * 60, p: rr0() * 6, amp: 0.0015 + rr0() * 0.004 }));
      const smax = W * 0.8, tmax = H * 0.8;
      for (let a = 0; a <= AS; a++) {
        const th = (a / AS) * Math.PI * 2, cs = Math.cos(th), sn = Math.sin(th);
        const rmax = Math.min(Math.abs(cs) > 1e-4 ? (smax - Math.sign(cs) * c[0]) / Math.abs(cs) : 9, Math.abs(sn) > 1e-4 ? (tmax - Math.sign(sn) * c[1]) / Math.abs(sn) : 9);
        for (let k = 0; k <= RS; k++) {
          const f = Math.pow(k / RS, 1.6), rr = radius + (Math.max(rmax, radius + 0.01) - radius) * f;
          const s = c[0] + cs * rr, t = c[1] + sn * rr;
          S._surf(s, t, P, N);
          const away = smooth(radius, radius + 0.04, rr);
          let zz = 0.0016 + away * 0.0016;
          for (const fo of folds) zz += Math.max(0, Math.sin((s * Math.cos(fo.a) + t * Math.sin(fo.a)) * fo.f + fo.p)) * fo.amp * away;
          P.addScaledVector(N, zz);
          const i = a * (RS + 1) + k;
          base[i * 3] = P.x; base[i * 3 + 1] = P.y; base[i * 3 + 2] = P.z;
          nrm[i * 3] = N.x; nrm[i * 3 + 1] = N.y; nrm[i * 3 + 2] = N.z;
          uvs[i * 2] = s * 7; uvs[i * 2 + 1] = t * 7;
        }
      }
      pos.set(base);
      const idx = [];
      for (let a = 0; a < AS; a++) for (let k = 0; k < RS; k++) { const i0 = a * (RS + 1) + k, i1 = i0 + RS + 1; idx.push(i0, i0 + 1, i1, i1, i0 + 1, i1 + 1); }
      const dg = keep(new THREE.BufferGeometry());
      dg.setAttribute('position', new THREE.BufferAttribute(pos, 3)); dg.setAttribute('uv', new THREE.BufferAttribute(uvs, 2)); dg.setIndex(idx);
      dg.computeVertexNormals();
      const mat = keep(new THREE.MeshPhysicalMaterial({ color: new THREE.Color(0x2f6c86), map: aT, normalMap: nT, normalScale: new THREE.Vector2(0.75, 0.75), roughness: 0.95, sheen: 0.75, sheenRoughness: 0.75, sheenColor: new THREE.Color(0x9ad8e6), side: THREE.DoubleSide, transparent: true, opacity: 0 }));
      const m = new THREE.Mesh(dg, mat);
      m.castShadow = true; m.receiveShadow = true;
      S.scene.add(m);
      // adhesive film ring around the window
      const ringG = keep(new THREE.RingGeometry(radius - 0.004, radius + 0.006, 120, 1));
      const rp = ringG.attributes.position;
      for (let i = 0; i < rp.count; i++) {
        const s = c[0] + rp.getX(i), t = c[1] - rp.getY(i);
        S._surf(s, t, P, N); P.addScaledVector(N, S.heightAt(S.stToUv(s, t)) + 0.0004);
        rp.setXYZ(i, P.x, P.y, P.z);
      }
      ringG.computeVertexNormals();
      const ringM = keep(new THREE.MeshPhysicalMaterial({ color: 0xffffff, transparent: true, opacity: 0, roughness: 0.06, clearcoat: 1, depthWrite: false, side: THREE.DoubleSide }));
      const ring = new THREE.Mesh(ringG, ringM);
      ring.renderOrder = 4;
      S.scene.add(ring);
      return {
        mesh: m,
        drop(k) {
          // falls from 6 cm, overshoots a touch and settles; opacity fades in on the way down
          const e = 1 - Math.pow(1 - clamp(k, 0, 1), 3);
          const lift = (1 - e) * 0.06 + Math.sin(clamp(k, 0, 1) * Math.PI) * 0.004;
          for (let i = 0; i < pos.length; i += 3) {
            pos[i] = base[i] + nrm[i] * lift; pos[i + 1] = base[i + 1] + nrm[i + 1] * lift; pos[i + 2] = base[i + 2] + nrm[i + 2] * lift;
          }
          dg.attributes.position.needsUpdate = true;
          mat.opacity = clamp(k * 2.2, 0, 1);
          mat.transparent = mat.opacity < 1;
          ringM.opacity = 0.16 * smooth(0.7, 1, k);
        },
      };
    }

    // hospital sheet under the body (fills the view past the curved skin patch)
    function sheet() {
      const wv = weave();
      const nT = tex(wv.normal, false), aT = tex(wv.albedo, true);
      nT.repeat.set(60, 60); aT.repeat.set(60, 60);
      const g = keep(new THREE.PlaneGeometry(2.4, 2.4, 80, 80));
      const p = g.attributes.position, r = U.rng(51);
      const folds = Array.from({ length: 6 }, () => ({ a: r() * Math.PI, f: 5 + r() * 12, p: r() * 6, amp: 0.002 + r() * 0.006 }));
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i), y = p.getY(i);
        let zz = 0;
        for (const f of folds) zz += Math.sin((x * Math.cos(f.a) + y * Math.sin(f.a)) * f.f + f.p) * f.amp;
        p.setZ(i, zz);
      }
      g.computeVertexNormals();
      const m = new THREE.Mesh(g, keep(new THREE.MeshPhysicalMaterial({ color: new THREE.Color(0x8fa4b2), map: aT, normalMap: nT, normalScale: new THREE.Vector2(0.5, 0.5), roughness: 0.95, sheen: 0.5, sheenColor: new THREE.Color(0xdfe9ef) })));
      m.rotation.x = -Math.PI / 2;
      const R = (S.shape && S.shape.R) || 0.26, Wd = S.patch.W;
      const edge = R * Math.cos(Math.min(1.45, (Wd / 2) / R)) - R;
      m.position.y = edge - 0.012;
      m.receiveShadow = true;
      S.scene.add(m);
      return m;
    }

    const api = {
      M, hand, pen, tube, drape, sheet,
      dispose() { bin.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } }); },
    };
    return api;
  }

  /* ─────────── skin ink: a private copy of the skin colour map we can draw on (marker ink,
                 areola, landmark pigment) — never touches the engine's shared cached canvas ─────────── */
  function Ink(S) {
    const THREE = window.THREE;
    const mat = S.skin && S.skin.material;
    const src = mat && mat.map && mat.map.image;
    if (!src || !src.width) return null;
    const c = cv(src.width, src.height), x = c.getContext('2d');
    x.drawImage(src, 0, 0);
    const t = new THREE.CanvasTexture(c);
    t.encoding = THREE.sRGBEncoding; t.anisotropy = 4;
    t.wrapS = mat.map.wrapS; t.wrapT = mat.map.wrapT;
    const old = mat.map;
    mat.map = t;
    const pxPerM = c.width / S.patch.W;
    const P = uv => [uv[0] * c.width, (1 - uv[1]) * c.height];
    let dirty = false;
    const api = {
      px: m => m * pxPerM,
      // marker stroke with a soft wet edge and slight bleed into the skin lines
      line(a, b, wM, col, alpha) {
        const pa = P(a), pb = P(b);
        x.save(); x.lineCap = 'round'; x.strokeStyle = col || 'rgba(76,36,140,1)';
        x.globalAlpha = (alpha === undefined ? 0.85 : alpha) * 0.35; x.lineWidth = wM * pxPerM * 1.8; x.filter = 'blur(1px)';
        x.beginPath(); x.moveTo(pa[0], pa[1]); x.lineTo(pb[0], pb[1]); x.stroke();
        x.filter = 'none'; x.globalAlpha = alpha === undefined ? 0.85 : alpha; x.lineWidth = wM * pxPerM;
        x.beginPath(); x.moveTo(pa[0], pa[1]); x.lineTo(pb[0], pb[1]); x.stroke();
        x.restore(); dirty = true;
      },
      cross(uv, sizeM, angle) {
        const sx = S.patch.W, sy = S.patch.H, h = sizeM / 2;
        [[angle + Math.PI / 4], [angle - Math.PI / 4]].forEach(([a]) => {
          const du = Math.cos(a) * h / sx, dv = Math.sin(a) * h / sy;
          api.line([uv[0] - du, uv[1] - dv], [uv[0] + du, uv[1] + dv], 0.0011);
        });
      },
      dashes(a, b, wM, dashM) {
        const L = S.distanceUv(a, b), n = Math.max(1, Math.floor(L / (dashM * 2)));
        for (let i = 0; i < n; i++) {
          const t0 = (i * 2) / (n * 2), t1 = (i * 2 + 1) / (n * 2);
          api.line([lerp(a[0], b[0], t0), lerp(a[1], b[1], t0)], [lerp(a[0], b[0], t1), lerp(a[1], b[1], t1)], wM, undefined, 0.6);
        }
      },
      // areola + nipple pigment (tone-aware), r in metres
      areola(uv, rM, tone) {
        const [px, py] = P(uv), r = rM * pxPerM;
        const dk = clamp(tone || 0.35, 0, 1);
        const g = x.createRadialGradient(px, py, 0, px, py, r);
        const c0 = `rgba(${Math.round(120 - dk * 60)},${Math.round(64 - dk * 30)},${Math.round(52 - dk * 26)},`;
        g.addColorStop(0, c0 + '0.85)'); g.addColorStop(0.3, c0 + '0.72)'); g.addColorStop(0.78, c0 + '0.5)'); g.addColorStop(1, c0 + '0)');
        x.save(); x.fillStyle = g; x.beginPath(); x.ellipse(px, py, r, r * 0.92, 0, 0, Math.PI * 2); x.fill();
        // Montgomery bumps (darker dots)
        const R = U.rng(7);
        x.fillStyle = c0 + '0.45)';
        for (let i = 0; i < 9; i++) { const a = R() * Math.PI * 2, d = r * (0.55 + R() * 0.3); x.beginPath(); x.arc(px + Math.cos(a) * d, py + Math.sin(a) * d, r * 0.05, 0, Math.PI * 2); x.fill(); }
        x.restore(); dirty = true;
      },
      flush() { if (dirty) { t.needsUpdate = true; dirty = false; } },
      dispose() { if (mat.map === t) mat.map = old; t.dispose(); },
    };
    return api;
  }

  /* palpation lens: ribs (and collarbone) under the fingers, drawn as a soft holographic overlay */
  function lensSVG(sh, cx, cy, r, curves, labels, alpha) {
    if (alpha <= 0.01) return '';
    let s = `<defs><radialGradient id="usLensG"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".72" stop-color="#fff" stop-opacity=".9"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
      <mask id="usLensM"><circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${r}" fill="url(#usLensG)"/></mask></defs>
      <g class="lens" style="opacity:${alpha.toFixed(2)}"><circle class="lr" cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${r}"/><g mask="url(#usLensM)">`;
    curves.forEach(cv2 => {
      const pts = cv2.pts.map(uv => sh.project(uv)).filter(p => p && p.visible);
      if (pts.length < 2) return;
      const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join('');
      s += `<path class="${cv2.cls}" d="${d}"/>`;
    });
    labels.forEach(l => {
      const p = sh.project(l.uv);
      if (!p || !p.visible || Math.hypot(p.x - cx, p.y - cy) > r * 0.92) return;
      s += `<text class="ll ${l.cls || ''}" x="${p.x.toFixed(1)}" y="${p.y.toFixed(1)}">${esc(l.t)}</text>`;
    });
    return s + '</g></g>';
  }

  /* ═════════════ CHEST DRAIN ═════════════ */
  function ChestDrainMode(app, d) {
    const side = d.side === 'left' ? 'left' : 'right';
    const STEPS_ALL = [
      ['mark', T('cd_s_mark', 'Find the spot')], ['clean', T('cd_s_clean', 'Clean the skin')], ['numb', T('cd_s_numb', 'Numb the skin')],
      ['cut', T('cd_s_cut', 'Cut along the rib')], ['dissect', T('cd_s_dissect', 'Through the chest wall')], ['sweep', T('cd_s_sweep', 'Finger sweep')],
      ['tube', T('cd_s_tube', 'Feed the tube')], ['connect', T('cd_s_connect', 'Connect the drain')],
    ];
    const STEPS = STEPS_ALL.filter(s => s[0] !== 'numb' || d.numbing);
    const tag = T('cd_tag', 'Chest drain · %s side', T('side_' + side, side));
    if (!window.NZA3D || !NZA3D.supported()) return Fallback(app, d, STEPS.map(s => s[1]), tag, { numbed: false });
    const ant = side === 'right' ? 1 : -1;                         // the front of the body lies toward +u on the right side
    const sh = Shell(app, d, {
      sub: tag,
      scene: { region: 'chest', size: [0.6, 0.44], hair: 0.22, focus: { uv: [0.5, 0.5], size: [0.12, 0.1] }, gravity: [-0.35 * ant, 1] },
    });
    const S = sh.S;
    if (!S) { sh.destroy(); return Fallback(app, d, STEPS.map(s => s[1]), tag, { numbed: false }); }
    const THREE = window.THREE;
    const MS = meshes(S);
    const ink = Ink(S);
    const H = S.patch.H, W = S.patch.W;
    // anatomy on the patch: ribs run down toward the front of the body
    const SP = 0.021 / H;                                          // rib spacing in v
    const slope = -0.12 * ant;
    const ribV = (n, u) => 0.5 + SP / 2 - (n - 5) * SP + slope * (u - 0.5);
    const target = [0.5, ribV(5, 0.5) - SP / 2];                   // 5th space, mid-axillary line
    for (let n = 3; n <= 9; n++) {
      for (let u = 0.17; u <= 0.835; u += 0.03) {
        const v = ribV(n, u);
        if (v < 0.06 || v > 0.94) continue;
        S.bumps.add({ uv: [u, v], radius: 0.015, height: 0.00125 * (1 - 0.35 * Math.abs(u - 0.5) * 2) });
      }
    }
    // muscle edges of the safe triangle: chest muscle (front), back muscle (behind), armpit hollow above
    S.bumps.add({ uv: [0.5 + 0.2 * ant, 0.7], radius: 0.075, height: 0.0055 });
    S.bumps.add({ uv: [0.5 + 0.13 * ant, 0.64], radius: 0.05, height: 0.003 });
    S.bumps.add({ uv: [0.5 - 0.2 * ant, 0.64], radius: 0.085, height: 0.006 });
    S.bumps.add({ uv: [0.5, 0.92], radius: 0.06, height: -0.004 });
    // nipple (anterior landmark: the 5th space runs at its level)
    const nip = [0.5 + 0.235 * ant, ribV(4, 0.5 + 0.235 * ant) - SP * 0.45];
    S.bumps.add({ uv: nip, radius: 0.0045, height: 0.0024 });
    if (ink) { ink.areola(nip, 0.014, d.tone !== undefined ? +d.tone : 0.35); ink.flush(); }
    // the camera moves with the work: wide to find the landmarks, close for the cut, back out for the tube
    const VIEW = { mark: [0.34, 0], clean: [0.28, 0], numb: [0.2, 0], cut: [0.19, 0], dissect: [0.19, 0], sweep: [0.21, 0], tube: [0.3, -0.05], connect: [0.32, -0.06] };
    function frameFor(id, instant) {
      const v = VIEW[id] || VIEW.mark;
      const c = id === 'mark' || !G.mark ? [0.5, 0.52] : [G.mark[0], G.mark[1] + v[1]];
      S.controls.frame(c, v[0], { pitch: id === 'mark' ? 1.08 : 1.16, instant: !!instant });
    }
    S.prewarm(['scalpel', 'forceps', 'gauze', 'syringe'], false);
    MS.sheet();
    const hand = MS.hand('palpate');
    const finger = MS.hand('point');
    const pen = MS.pen();
    let drape = null;

    const ml0 = Math.max(0, d.haemo || 0), air = (d.ptx || 0) > 0;
    const G = {
      step: 0, t: 0, tool: null, mark: null, markErr: null, markSpace: null,
      cover: 0, numb: 0, numbed: false, numbSkipped: false, wheal: null,
      wound: null, cutStart: null, cutDir: null, cutLen: 0, cutDev: [], cutDone: false,
      wall: 0, popped: false, spread: 0, offT: 0,
      sweep: 0, lastAng: null,
      tube: null, depth: 0, dragY: null, tubeSet: false,
      connected: false, drained: 0, lung: 0, bubbles: 0, drainT: 0,
      flinches: 0, done: false, score: {}, lens: 0, felt: {}, drapeK: -1,
    };
    const tools = [
      { key: '1', id: 'hand', label: T('cd_t_hand', 'Palpate'), icon: 'hand' },
      { key: '2', id: 'pen', label: T('cd_t_pen', 'Skin marker'), icon: 'edit' },
      { key: '3', id: 'swab', label: T('cd_t_swab', 'Antiseptic'), icon: 'drop' },
      { key: '4', id: 'lido', label: T('cd_t_lido', 'Lidocaine'), icon: 'syringe', hide: !d.numbing },
      { key: '5', id: 'scalpel', label: T('cd_t_scalpel', 'Scalpel'), icon: 'scalpel' },
      { key: '6', id: 'clamp', label: T('cd_t_clamp', 'Curved clamp'), icon: 'forceps' },
      { key: '7', id: 'finger', label: T('cd_t_finger', 'Finger'), icon: 'hand' },
      { key: '8', id: 'tube', label: T('cd_t_tube', 'Chest tube'), icon: 'tube' },
      { key: '9', id: 'drain', label: T('cd_t_drain', 'Drain unit'), icon: 'kit' },
    ].filter(t => !t.hide);
    const STEP_TOOL = { mark: 'pen', clean: 'swab', numb: 'lido', cut: 'scalpel', dissect: 'clamp', sweep: 'finger', tube: 'tube', connect: 'drain' };
    const stepId = () => (STEPS[G.step] || STEPS[STEPS.length - 1])[0];
    const TXT = {
      mark: T('cd_x_mark', 'Feel for the ribs with {1}: hold {LMB} and sweep down from the armpit, they light up under your fingers. Then mark the **5th rib space in the middle of the armpit line** with {2}.'),
      clean: T('cd_x_clean', 'Hold {LMB} and scrub the antiseptic over the mark until the whole area is brown. The sterile drape goes on after.'),
      numb: T('cd_x_numb', 'Hold {LMB} on the mark to raise a bleb of lidocaine, then down to the top of the rib. {N} skips it (it will hurt).'),
      cut: T('cd_x_cut', 'Press at one end of the dashed line and draw the blade **along the top of the rib**, 2–3 cm.'),
      dissect: T('cd_x_dissect', 'Put the closed clamp in the cut and hold {LMB} to push through the muscle until it **pops** into the chest. Then tap {Space} to spread the jaws.'),
      sweep: T('cd_x_sweep', 'Finger in the hole: hold {LMB} and circle around it to clear the track and feel the lung.'),
      tube: T('cd_x_tube', 'Hold {LMB} and drag **toward the head** to feed the tube up and back. Stop at **10–14 cm** and press {Enter} to clamp it there.'),
      connect: T('cd_x_connect', 'Click the drain ({9}) to connect the tube and open the clamp.'),
    };
    const pp = NZA.ui.ProcPanel(sh.ppHost, {
      tag, step: 1, total: STEPS.length, steps: STEPS.map(s => s[1]),
      title: STEPS[0][1], text: TXT.mark,
      wide: { label: T('cd_w_mark', 'Off target'), value: '--', unit: 'mm', meter: { value: 0, zone: [0, 0.2] } },
      stats: [
        { id: 'spo2', label: 'SpO₂', value: String(d.vitals && d.vitals.spo2 || '--'), unit: '%' },
        { id: 'rr', label: T('st_rr', 'Resp'), value: String(d.vitals && d.vitals.rr || '--'), unit: '/min' },
        { id: 'hr', label: T('st_hr', 'Pulse'), value: String(d.vitals && (d.vitals.hr || d.vitals.ecgRate) || '--') },
      ],
      tools: tools.map(t => ({ key: t.key, label: t.label, icon: t.icon })),
      hints: [{ keys: [T('k_rmb', 'RMB')], label: T('h_look3', 'look around') }, { keys: [T('k_wheel', 'Wheel')], label: T('h_zoom', 'zoom') }, { keys: ['R'], label: T('h_recentre', 'recentre') }],
      abort: { label: T('hold_stop_needle', 'Hold to stop'), key: 'ESC', seconds: 1.2 },
      onAbort: () => app.abort(),
      onTool: k => pick(k),
    });

    // drain unit widget (top-right)
    const dw = document.createElement('section');
    dw.className = 'us-drw nza-hud solid';
    dw.innerHTML = `
      <header><span class="k">${esc(T('dr_title', 'Drain unit'))}<em>UWS-3 · ${esc(T('dr_sub', '3-chamber'))}</em></span><span class="st">${esc(T('dr_idle', 'not connected'))}</span></header>
      <div class="dr-body">
        <svg class="dr-svg" viewBox="0 0 150 128">
          <defs><linearGradient id="usDrB" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a3161b"/><stop offset="1" stop-color="#4a0507"/></linearGradient>
            <linearGradient id="usDrW" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3fd0ff" stop-opacity=".55"/><stop offset="1" stop-color="#0b6f99" stop-opacity=".75"/></linearGradient>
            <linearGradient id="usDrG" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity=".1"/><stop offset=".3" stop-color="#fff" stop-opacity=".02"/><stop offset="1" stop-color="#fff" stop-opacity=".06"/></linearGradient></defs>
          <rect class="case" x="2" y="2" width="146" height="124" rx="10"/>
          <rect class="ch" x="10" y="12" width="74" height="104" rx="4"/>
          <rect class="lvl" x="11" y="115" width="72" height="0" fill="url(#usDrB)"/>
          <path class="mns" d="M11 115 Q47 112 83 115" fill="none"/>
          <g class="grad"></g>
          <rect class="ch" x="92" y="12" width="22" height="104" rx="4"/>
          <rect class="wat" x="93" y="70" width="20" height="45" fill="url(#usDrW)"/>
          <g class="bub"></g>
          <rect class="ch" x="120" y="12" width="22" height="104" rx="4"/>
          <rect class="wat2" x="121" y="40" width="20" height="75" fill="url(#usDrW)"/>
          <rect x="10" y="12" width="132" height="104" rx="4" fill="url(#usDrG)" pointer-events="none"/>
          <text class="lb" x="47" y="124">${esc(T('dr_col', 'COLLECT'))}</text><text class="lb" x="103" y="124">${esc(T('dr_seal', 'SEAL'))}</text><text class="lb" x="131" y="124">${esc(T('dr_suc', 'SUCT'))}</text>
        </svg>
        <div class="dr-read">
          <div class="r"><span>${esc(T('dr_drained', 'Drained'))}</span><b class="dml"></b></div>
          <div class="r"><span>${esc(T('dr_rate', 'Flow'))}</span><b class="drate">--</b></div>
          <div class="r"><span>${esc(T('dr_air', 'Air leak'))}</span><b class="dair">--</b></div>
          <div class="lung"><svg viewBox="0 0 44 44"><circle class="bg" cx="22" cy="22" r="18"/><circle class="fg" cx="22" cy="22" r="18" stroke-dasharray="0 120"/></svg><div><span>${esc(T('dr_lung', 'Lung open'))}</span><b class="dl">0%</b></div></div>
        </div>
      </div>`;
    app.ui.appendChild(dw);
    let gs = '';
    for (let i = 0; i <= 2000; i += 250) { const y = 115 - i / 2000 * 100; gs += `<line x1="70" y1="${y.toFixed(1)}" x2="${i % 500 ? 78 : 82}" y2="${y.toFixed(1)}"/>${i % 500 === 0 && i ? `<text x="66" y="${(y + 2.5).toFixed(1)}">${i}</text>` : ''}`; }
    dw.querySelector('.grad').innerHTML = gs;
    const odo = NZA.ui.FlipClock(dw.querySelector('.dml'), { value: '0000', small: true });

    sh.patient([
      { id: 'side', label: T('pt_side', 'Side'), value: T('side_' + side, side) },
      { id: 'blood', label: T('pt_blood', 'Blood in chest'), value: ml0 ? `~${ml0} mL` : '—', tone: ml0 > 1000 ? 'red' : ml0 ? 'amber' : '' },
      { id: 'air', label: T('pt_air', 'Air in chest'), value: air ? `${d.ptx}%${d.tension ? ' · ' + T('pt_tension', 'tension') : ''}` : '—', tone: d.tension ? 'red' : air ? 'amber' : '' },
      { id: 'numb', label: T('pt_numb', 'Local anaesthetic'), value: d.numbing ? T('pt_numb_no', 'not yet') : T('pt_numb_none', 'none carried'), tone: d.numbing ? '' : 'amber' },
    ]);

    function pick(key) {
      const t = tools.find(x => x.key === String(key));
      if (!t || G.done) return;
      G.tool = t.id;
      pp.active(t.key);
      const engine = { swab: 'gauze', lido: 'syringe', scalpel: 'scalpel', clamp: 'forceps', hand: hand, pen: pen, finger: finger }[t.id] || null;
      S.tools.use(engine);
      if (t.id === 'drain' && stepId() === 'connect') connect();
      NZA.audio.click(640);
    }
    function nextStep() {
      G.step++;
      if (G.step >= STEPS.length) return;
      const id = stepId();
      frameFor(id, false);
      pp.set({ step: G.step + 1, title: STEPS[G.step][1], text: TXT[id] });
      const tl = tools.find(t => t.id === STEP_TOOL[id]);
      if (tl) pick(tl.key);
      wideFor(id);
      NZA.audio.success();
      const doneKeys = tools.filter(t => Object.keys(STEP_TOOL).slice(0, Object.keys(STEP_TOOL).indexOf(id)).some(s => STEP_TOOL[s] === t.id)).map(t => t.key);
      doneKeys.forEach(k => pp.tool(k, 'done'));
      if (tl) pp.active(tl.key);
    }
    function wideFor(id) {
      const Wd = {
        mark: { label: T('cd_w_mark', 'Off target'), value: '--', unit: 'mm', meter: { value: 0, zone: [0, 0.2] } },
        clean: { label: T('cd_w_clean', 'Covered'), value: '0', unit: '%', meter: { value: 0, zone: [0.85, 1] } },
        numb: { label: T('cd_w_numb', 'Lidocaine'), value: '0', unit: 'mL', meter: { value: 0, zone: [0.8, 1] } },
        cut: { label: T('cd_w_cut', 'Incision'), value: '0', unit: 'mm', meter: { value: 0, zone: [0.55, 0.9] } },
        dissect: { label: T('cd_w_dissect', 'Through the wall'), value: '0', unit: '%', meter: { value: 0, zone: [0.95, 1] } },
        sweep: { label: T('cd_w_sweep', 'Track cleared'), value: '0', unit: '%', meter: { value: 0, zone: [0.95, 1] } },
        tube: { label: T('cd_w_tube', 'Tube depth'), value: '0.0', unit: 'cm', meter: { value: 0, zone: [10 / 18, 14 / 18] } },
        connect: { label: T('cd_w_connect', 'Drained'), value: '0', unit: 'mL', meter: { value: 0 } },
      }[id];
      if (Wd) pp.set({ wide: Wd });
    }
    pick('1');
    frameFor('mark', true);

    function ribAt(uv) {
      // which rib / space lies under a patch point
      for (let n = 2; n <= 11; n++) {
        const dv = uv[1] - ribV(n, uv[0]);
        if (Math.abs(dv) < SP * 0.3) return { rib: n };
      }
      for (let n = 2; n <= 11; n++) {
        if (uv[1] < ribV(n, uv[0]) && uv[1] > ribV(n + 1, uv[0])) return { space: n };
      }
      return {};
    }
    const mmBetween = (a, b) => S.distanceUv(a, b) / MM;

    // ── input ──
    S.on('down', (e) => {
      if (e.button !== 0 || G.done) return;
      G.lmb = true;
      const hit = sh.hit();
      const id = stepId();
      if (!hit) return;
      if (G.tool === 'pen' && id === 'mark') placeMark(hit.uv);
      if (G.tool === 'scalpel' && id === 'cut' && !G.cutDone) startCut(hit.uv);
      if (G.tool === 'tube' && id === 'tube') G.dragY = sh.state.mouse.cy;
      if (G.tool === 'drain' && id === 'connect') connect();
      S.tools.press(true);
    });
    S.on('up', (e) => { if (e.button !== 0) return; G.lmb = false; S.tools.press(false); if (G.cutStart && !G.cutDone) endCut(); G.dragY = null; });

    function placeMark(uv) {
      G.mark = uv;
      G.markErr = mmBetween(uv, target);
      const where = ribAt(uv);
      G.markSpace = where;
      // ink: an X on the spot and a short stroke along the rib below it
      if (ink) {
        ink.cross(uv, 0.009, -Math.atan(slope * H / W));
        const half = 0.012 / W;
        ink.line([uv[0] - half, uv[1] - slope * half - SP * 0.42], [uv[0] + half, uv[1] + slope * half - SP * 0.42], 0.0009, undefined, 0.6);
        ink.flush();
      } else S.markers.set('mark', { uv, kind: 'cross', color: 0x5b2f9c, size: 0.007, opacity: 0.95, pulse: false });
      const errTone = G.markErr <= 10 ? 'ok' : G.markErr <= 20 ? 'warn' : 'bad';
      const whereTxt = where.rib ? T('cd_on_rib', 'on the %s rib', ORD(where.rib)) : where.space ? T('cd_in_space', 'in the %s space', ORD(where.space)) : '';
      pp.wide({ value: String(Math.round(G.markErr)), meter: { value: clamp(G.markErr / 50, 0, 1), zone: [0, 0.2], tone: errTone === 'ok' ? '' : errTone === 'warn' ? 'amber' : 'red' }, caption: whereTxt });
      pp.flash(errTone, errTone === 'ok' ? T('cd_fl_mark_ok', 'Good spot: %s, in the safe triangle.', whereTxt) : T('cd_fl_mark_off', 'Marked %s, %s mm from the ideal spot.', whereTxt, Math.round(G.markErr)), 3200);
      NZA.audio.click(900);
      G.score.mark = G.markErr <= 8 ? 25 : G.markErr <= 15 ? 19 : G.markErr <= 25 ? 11 : 4;
      if (where.rib) G.score.mark -= 4;
      if (G.felt && Object.keys(G.felt).length >= 3) G.score.mark += 2;
      G.showTri = 3.2;
      setTimeout(() => { if (!G.done && stepId() === 'mark') nextStep(); }, 900);
    }

    // incision runs along the rib below the mark (its upper border)
    function cutLine() {
      const m = G.mark || target;
      const n = Math.round(((0.5 + SP / 2 - m[1] + slope * (m[0] - 0.5)) / SP) + 5);
      const below = Math.max(n, 3);
      const vTop = ribV(below, m[0]);
      const v0 = Math.min(m[1], vTop + SP * 0.32);
      const half = 0.016 / W;
      return { a: [m[0] - half, v0 - slope * half], b: [m[0] + half, v0 + slope * half], mid: [m[0], v0] };
    }
    function startCut(uv) {
      const L = cutLine();
      const dA = mmBetween(uv, L.a), dB = mmBetween(uv, L.b);
      if (Math.min(dA, dB) > 9) { pp.flash('warn', T('cd_fl_cut_start', 'Start at one end of the dashed line.'), 2000); return; }
      const from = dA < dB ? L.a : L.b, to = dA < dB ? L.b : L.a;
      const dir = [to[0] - from[0], to[1] - from[1]];
      G.cutStart = from; G.cutDir = dir;
      const pts = [];
      for (let i = 0; i <= 12; i++) pts.push([from[0] + dir[0] * i / 12, from[1] + dir[1] * i / 12]);
      G.wound = S.wounds.add({ type: 'incision', points: pts, cut: 0.001, gape: 2.2 * MM, depth: 5 * MM, open: 1, seed: (d.seed || 7) % 9973 });
      if (!G.numbed) flinch();
    }
    function endCut() {
      G.cutDone = G.cutLen >= 14;
      if (!G.cutDone) { pp.flash('warn', T('cd_fl_cut_short', 'Too short: press on the end of the cut and keep going.'), 2600); G.cutStart = null; return; }
      const dev = G.cutDev.length ? G.cutDev.reduce((a, b) => a + b, 0) / G.cutDev.length : 0;
      G.score.cut = (G.cutLen >= 22 && G.cutLen <= 36 ? 15 : G.cutLen >= 16 ? 10 : 5) + (dev <= 3 ? 5 : dev <= 6 ? 2 : 0);
      S.fluids.bleed(G.wound, 1.6);
      pp.flash('ok', T('cd_fl_cut_ok', 'Incision %s mm along the rib.', Math.round(G.cutLen)), 2400);
      setTimeout(() => { if (!G.done && stepId() === 'cut') nextStep(); }, 600);
    }
    function flinch() {
      if (G.numbed) return;
      G.flinches++;
      S.controls.shake(0.5, 380);
      app.post('flinch', { pain: 70 });
    }

    function connect() {
      if (G.connected || stepId() !== 'connect') return;
      G.connected = true;
      dw.classList.add('on');
      dw.querySelector('.st').textContent = T('dr_on', 'draining');
      if (G.tube) G.tube.open(true);
      NZA.audio.click(520);
      G.score.connect = 5;
    }

    function finish() {
      if (G.done) return;
      G.done = true;
      S.tools.use(null);
      const s = G.score;
      const total = clamp(Math.round((s.mark || 0) + (s.clean || 0) + (s.numb || 0) + (s.cut || 0) + (s.dissect || 0) + (s.sweep || 0) + (s.tube || 0) + (s.connect || 0) - G.flinches * 2), 0, 100);
      pp.set({ title: T('reading_peri', 'Checking the result…'), text: '' });
      app.post('finish', { result: { score: total, numbed: G.numbed, drained: Math.round(G.drained), depth: +G.depth.toFixed(1) } }).then(r => { if (r && r.outcome) api.msg.result(r.outcome); });
    }

    // rib curves for the palpation lens
    const ribCurves = [];
    for (let n = 2; n <= 10; n++) {
      const pts = [];
      for (let u = 0.08; u <= 0.92; u += 0.04) pts.push([u, ribV(n, u)]);
      ribCurves.push({ cls: n === 5 || n === 6 ? 'rb hi' : 'rb', pts });
    }
    const ribLabels = [];
    for (let n = 2; n <= 10; n++) ribLabels.push({ uv: [0.5 + 0.06 * ant, ribV(n, 0.5 + 0.06 * ant) + SP * 0.08], t: String(n), cls: n === 5 || n === 6 ? 'hi' : '' });
    for (let n = 2; n <= 9; n++) ribLabels.push({ uv: [0.5 - 0.075 * ant, ribV(n, 0.5 - 0.075 * ant) - SP * 0.42], t: `${n}`, cls: n === 5 ? 'sp hi' : 'sp' });

    // ── per frame ──
    let uiT = 0;
    const camRight = new THREE.Vector3();
    function frame(dt) {
      G.t += dt;
      const id = stepId();
      const hit = sh.hit();
      const L = G.mark ? cutLine() : null;
      let ring = null, rtext = '', rtone = '';
      // overlay guides (projected each frame)
      let ov = '';
      const P = uv => sh.project(uv);
      // palpation lens (ribs light up under the fingers while pressing with the hand)
      const pressing = id === 'mark' && G.tool === 'hand' && G.lmb && hit;
      G.lens = clamp(G.lens + (pressing ? dt * 4 : -dt * 3), 0, 1);
      if (G.lens > 0 && sh.state.moved) ov += lensSVG(sh, sh.state.mouse.cx, sh.state.mouse.cy, 170, ribCurves, ribLabels, G.lens);
      if (G.showTri > 0) {
        G.showTri = Math.max(0, (G.showTri || 0) - dt);
        const alpha = clamp(G.showTri, 0, 1);
        const apex = P([0.5, 0.86]), a1 = P([0.5 + 0.11 * ant, ribV(5, 0.5 + 0.11 * ant) - SP / 2]), a2 = P([0.5 - 0.11 * ant, ribV(5, 0.5 - 0.11 * ant) - SP / 2]);
        ov += `<path class="tri" style="opacity:${alpha.toFixed(2)}" d="M${apex.x} ${apex.y}L${a1.x} ${a1.y}L${a2.x} ${a2.y}Z"/>`;
        const tg = P(target);
        ov += `<circle class="tgt" style="opacity:${alpha.toFixed(2)}" cx="${tg.x}" cy="${tg.y}" r="7"/>`;
        const lb = P([0.5, 0.79]);
        ov += `<g class="trl" style="opacity:${alpha.toFixed(2)}" transform="translate(${lb.x.toFixed(1)} ${lb.y.toFixed(1)})"><rect x="-58" y="-11" width="116" height="20" rx="5"/><text y="3">${esc(T('cd_safe', 'SAFE TRIANGLE'))}</text></g>`;
      }
      if (L && (id === 'cut')) {
        const a = P(L.a), b = P(L.b);
        ov += `<line class="guide" x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}"/><circle class="gend" cx="${a.x}" cy="${a.y}" r="5"/><circle class="gend" cx="${b.x}" cy="${b.y}" r="5"/>`;
      }
      sh.svg.innerHTML = ov;

      // drape drop after the skin prep
      if (G.drapeK >= 0 && G.drapeK < 1) {
        G.drapeK = Math.min(1, G.drapeK + dt / 0.85);
        if (drape) drape.drop(G.drapeK);
      }

      // ── step logic ──
      if (id === 'mark' && hit && G.tool === 'hand' && G.lmb) {
        const w = ribAt(hit.uv);
        rtext = w.rib ? T('cd_rib', '%s rib', ORD(w.rib)) : w.space ? T('cd_space', '%s space', ORD(w.space)) : '';
        rtone = w.space === 5 && Math.abs(hit.uv[0] - 0.5) < 0.06 ? 'teal' : '';
        ring = 1;
        if (w.rib && G.lastRib !== w.rib) { G.lastRib = w.rib; G.felt[w.rib] = true; NZA.audio.tick(); }
      } else if (id === 'mark' && hit && G.tool === 'pen') {
        const w = ribAt(hit.uv);
        rtext = w.rib ? T('cd_rib', '%s rib', ORD(w.rib)) : w.space ? T('cd_space', '%s space', ORD(w.space)) : '';
        ring = rtext ? 0 : null;
      }

      if (id === 'clean' && G.tool === 'swab' && G.lmb && hit && G.mark) {
        S.layers.paint('iodine', hit.uv, 0.019, Math.min(1, dt * 3.4), { hardness: 0.3, grain: 0.55 });
        S.layers.paint('wet', hit.uv, 0.02, Math.min(1, dt * 2), { hardness: 0.3 });
        G.cover = S.layers.coverage('iodine', G.mark, 0.04, 0.3);
        pp.wide({ value: String(Math.round(G.cover * 100)), meter: { value: G.cover, zone: [0.85, 1] } });
        if (G.cover >= 0.86) {
          G.score.clean = 10;
          // sterile field: the drape with its window settles over the prepped skin
          try { drape = MS.drape(G.mark, 0.052); G.drapeK = 0; } catch (e) { console.warn('[ultrasound] drape', e); }
          NZA.audio.noise(420, { vol: 0.05, lp: 1400, hp: 120, attack: 0.05, release: 0.4 });
          pp.flash('ok', T('cd_fl_draped', 'Prepped. The sterile drape is on.'), 2200);
          nextStep();
        }
      }
      if (id === 'numb' && G.tool === 'lido' && G.lmb && hit && G.mark) {
        const near = mmBetween(hit.uv, G.mark) < 8;
        if (near) {
          G.numb = Math.min(1, G.numb + dt / 2.6);
          if (!G.wheal) G.wheal = S.bumps.add({ uv: G.mark, radius: 0.004, height: 0.0002 });
          G.wheal.set({ radius: 0.004 + 0.007 * G.numb, height: 0.0002 + 0.0016 * G.numb });
          ring = G.numb; rtext = `${(G.numb * 5).toFixed(1)} mL`; rtone = 'teal';
          pp.wide({ value: (G.numb * 5).toFixed(1), meter: { value: G.numb, zone: [0.8, 1] } });
          if (G.numb >= 1) { G.numbed = true; G.score.numb = 5; sh.row('numb', T('pt_numb_yes', '5 mL lidocaine'), 'teal'); pp.flash('ok', T('cd_fl_numb', 'Skin and rib top numbed.'), 2200); nextStep(); }
        } else { ring = 0; rtext = T('cd_on_mark', 'on the mark'); rtone = 'amber'; }
      }
      if (id === 'cut' && G.cutStart && !G.cutDone && G.lmb && hit) {
        const v = [hit.uv[0] - G.cutStart[0], hit.uv[1] - G.cutStart[1]];
        const len2 = G.cutDir[0] * G.cutDir[0] + G.cutDir[1] * G.cutDir[1];
        const tN = clamp((v[0] * G.cutDir[0] + v[1] * G.cutDir[1]) / len2, 0, 1);
        const onLine = [G.cutStart[0] + G.cutDir[0] * tN, G.cutStart[1] + G.cutDir[1] * tN];
        const dev = mmBetween(hit.uv, onLine);
        const fullLen = S.distanceUv(G.cutStart, [G.cutStart[0] + G.cutDir[0], G.cutStart[1] + G.cutDir[1]]) / MM;
        if (dev < 6) {
          const newLen = tN * fullLen;
          if (newLen > G.cutLen) {
            G.cutLen = newLen; G.cutDev.push(dev);
            G.wound.set({ cut: clamp(tN, 0.001, 1) });
            if (Math.random() < dt * 6) S.layers.splat('blood', onLine, 0.0016, 0.35);
          }
          ring = clamp(G.cutLen / 30, 0, 1); rtext = `${Math.round(G.cutLen)} mm`; rtone = G.cutLen > 36 ? 'red' : 'teal';
          if (G.cutLen >= 36 || tN >= 0.999) { G.lmb = false; S.tools.press(false); endCut(); }
        } else { ring = clamp(G.cutLen / 30, 0, 1); rtext = T('cd_keep_line', 'stay on the line'); rtone = 'red'; }
        pp.wide({ value: String(Math.round(G.cutLen)), meter: { value: clamp(G.cutLen / 40, 0, 1), zone: [0.55, 0.9] } });
      }
      if (id === 'dissect' && G.wound) {
        const mid = G.wound.at(0.5).uv;
        const onCut = hit && G.wound.locate(hit.uv).d < 5 * MM;
        if (G.tool === 'clamp' && G.lmb && !G.popped) {
          if (onCut) {
            G.wall = Math.min(1, G.wall + dt / 3.4);
            S.controls.shake(0.06, 120);
            G.wound.set({ open: 1 + G.wall * 1.4, depth: (5 + G.wall * 7) * MM });
            if (!G.numbed && Math.random() < dt * 0.6) flinch();
          } else G.offT += dt;
          ring = G.wall; rtext = onCut ? `${Math.round(G.wall * 100)}%` : T('cd_in_cut', 'tip in the cut'); rtone = onCut ? 'teal' : 'amber';
          if (G.wall >= 1) {
            G.popped = true;
            NZA.audio.tone(140, 120, { vol: 0.12, type: 'triangle' });
            S.controls.shake(0.4, 260);
            if (ml0 > 0) {
              S.fluids.bleed(G.wound, 14);
              for (let i = 0; i < 6; i++) S.layers.splat('blood', [mid[0] + (Math.random() - 0.5) * 0.03, mid[1] - Math.random() * 0.05], 0.004 + Math.random() * 0.004, 0.7);
              S.fluids.drops(S.surfaceAt(mid).point, 18, 0x5e0508);
              pp.flash('ok', T('cd_fl_pop_blood', 'Pop! Dark blood wells up out of the chest.'), 2800);
            } else {
              NZA.audio.noise(900, { vol: 0.08, lp: 3200, hp: 600 });
              pp.flash('ok', T('cd_fl_pop_air', 'Pop! A hiss of air escapes.'), 2800);
            }
          }
        }
        if (G.popped && G.spread >= 3) { G.score.dissect = G.offT < 1.5 ? 10 : G.offT < 4 ? 6 : 3; nextStep(); }
        pp.wide({ value: String(Math.round(G.wall * 100)), meter: { value: G.wall, zone: [0.95, 1] }, caption: G.popped ? T('cd_spread_n', 'spread %s/3', G.spread) : '' });
      }
      if (id === 'sweep' && G.wound) {
        const mid = G.wound.at(0.5);
        const pm = sh.project(mid.uv);
        const ang = Math.atan2(sh.state.mouse.cy - pm.y, sh.state.mouse.cx - pm.x);
        // the finger stays in the hole and circles with the pointer
        if (G.tool === 'finger') {
          S.tools.follow = false;
          const base = S.surfaceAt(mid.uv);
          const sw = 0.0035;
          const pt = base.point.clone().add(new THREE.Vector3(Math.cos(ang) * sw, 0, Math.sin(ang) * sw));
          S.tools.hit = { point: pt, normal: base.normal, uv: mid.uv, s: S.uvToST(mid.uv)[0], t: S.uvToST(mid.uv)[1] };
          finger.group.visible = true;
        }
        if (G.lmb && G.tool === 'finger') {
          if (G.lastAng !== null) {
            let da = ang - G.lastAng;
            while (da > Math.PI) da -= 2 * Math.PI;
            while (da < -Math.PI) da += 2 * Math.PI;
            if (Math.abs(da) < 1.2) G.sweep = Math.min(1, G.sweep + Math.abs(da) / (Math.PI * 4));
          }
          G.lastAng = ang;
          ring = G.sweep; rtext = `${Math.round(G.sweep * 100)}%`; rtone = 'teal';
          if (Math.random() < dt * 3) S.controls.shake(0.04, 90);
        } else G.lastAng = null;
        pp.wide({ value: String(Math.round(G.sweep * 100)), meter: { value: G.sweep, zone: [0.95, 1] } });
        if (G.sweep >= 1) { G.score.sweep = 5; S.tools.follow = true; pp.flash('ok', T('cd_fl_sweep', 'Track clear, no stuck lung under the finger.'), 2200); nextStep(); }
      }
      if (id !== 'sweep' && !S.tools.follow) S.tools.follow = true;
      if (id === 'tube' && G.wound) {
        if (!G.tube) {
          const mid = G.wound.at(0.5).uv;
          const sf = S.surfaceAt(mid);
          // outside part: from the skin, out and away toward the drain (screen bottom / back of the body)
          const n = sf.normal.clone();
          camRight.setFromMatrixColumn(S.camera.matrixWorld, 0);
          const down = new THREE.Vector3().setFromMatrixColumn(S.camera.matrixWorld, 1).negate();
          const p0 = sf.point.clone().addScaledVector(n, -0.003);
          const p1 = p0.clone().addScaledVector(n, 0.03).addScaledVector(down, 0.01);
          const p2 = p0.clone().addScaledVector(n, 0.06).addScaledVector(down, 0.07).addScaledVector(camRight, -0.03 * ant);
          const p3 = p0.clone().addScaledVector(n, 0.05).addScaledVector(down, 0.2).addScaledVector(camRight, -0.09 * ant);
          G.tube = MS.tube(new THREE.CatmullRomCurve3([p0, p1, p2, p3], false, 'catmullrom', 0.4));
          G.tube.depth(0);
        }
        if (G.lmb && G.tool === 'tube' && !G.tubeSet && G.dragY !== null) {
          const dy = G.dragY - sh.state.mouse.cy;
          if (dy > 0) { G.depth = clamp(G.depth + dy * 0.035, 0, 18); G.dragY = sh.state.mouse.cy; }
          if (dy < -2) { G.depth = clamp(G.depth + dy * 0.02, 0, 18); G.dragY = sh.state.mouse.cy; }
          ring = clamp(G.depth / 18, 0, 1); rtext = `${G.depth.toFixed(1)} cm`; rtone = G.depth >= 10 && G.depth <= 14 ? 'teal' : G.depth > 14 ? 'red' : '';
          if (!G.numbed && G.depth > 4 && Math.random() < dt * 0.4) flinch();
        }
        G.tube.depth(G.depth);
        if (ml0 > 0 && G.depth > 3) G.tube.fill(Math.min(0.45, (G.depth - 3) / 25));
        pp.wide({ value: G.depth.toFixed(1), meter: { value: G.depth / 18, zone: [10 / 18, 14 / 18], tone: G.depth > 14 ? 'red' : '' }, caption: G.depth < 9 ? T('cd_cap_short', 'side hole still outside') : G.depth > 14 ? T('cd_cap_deep', 'too far: pull back') : T('cd_cap_good', 'all holes inside') });
      }
      if (id === 'connect' && G.tube) {
        G.tube.depth(G.depth);
        if (G.connected) {
          G.drainT += dt;
          const goal = ml0 * 0.85 * (0.6 + 0.4 * (G.score.tube || 10) / 20);
          const before = G.drained;
          G.drained = Math.min(goal, G.drained + Math.max(30, goal / 6) * dt);
          G.flow = dt > 0 ? (G.drained - before) / dt * 60 : 0;
          G.lung = Math.min(1, G.drainT / 7);
          G.tube.fill(ml0 > 0 ? Math.min(1, 0.45 + G.drainT / 2) : 0);
          odo.set(String(Math.round(G.drained)).padStart(4, '0'));
          pp.wide({ value: String(Math.round(G.drained)), meter: { value: goal ? G.drained / goal : G.lung } });
          if (G.drainT >= 7.5 && !G.done) finish();
        }
      }
      // drain widget animation
      const lvl = Math.min(100, G.drained / 2000 * 100);
      dw.querySelector('.lvl').setAttribute('y', (115 - lvl).toFixed(1));
      dw.querySelector('.lvl').setAttribute('height', lvl.toFixed(1));
      dw.querySelector('.mns').setAttribute('d', `M11 ${(115 - lvl).toFixed(1)} Q47 ${(112 - lvl + Math.sin(G.t * 3) * 0.8).toFixed(1)} 83 ${(115 - lvl).toFixed(1)}`);
      const airNow = G.connected && air && G.lung < 0.95;
      if (G.connected) {
        G.bubbles += dt;
        const bub = dw.querySelector('.bub');
        if (airNow) {
          let b = '';
          for (let i = 0; i < 6; i++) { const ph = (G.bubbles * 1.6 + i * 0.17) % 1; b += `<circle cx="${(97 + (i % 3) * 5).toFixed(1)}" cy="${(114 - ph * 42).toFixed(1)}" r="${(1.2 + (i % 2) * 0.9).toFixed(1)}"/>`; }
          bub.innerHTML = b;
        } else bub.innerHTML = '';
        const sw = Math.sin(G.bubbles * 2.4) * 3 * (1 - G.lung);
        dw.querySelector('.wat').setAttribute('y', (70 + sw).toFixed(1));
        dw.querySelector('.dair').textContent = airNow ? T('dr_bubbling', 'bubbling') : T('dr_none', 'none');
        dw.querySelector('.dair').className = `dair ${airNow ? 'amber' : 'teal'}`;
        dw.querySelector('.drate').textContent = G.flow > 1 ? `${Math.round(G.flow)} mL/min` : T('dr_slow', 'slowing');
        const C = 2 * Math.PI * 18;
        dw.querySelector('.lung .fg').setAttribute('stroke-dasharray', `${(C * G.lung).toFixed(1)} ${C.toFixed(1)}`);
        dw.querySelector('.dl').textContent = `${Math.round(G.lung * 100)}%`;
      }
      sh.ring(ring, rtext, rtone);
      uiT += dt;
      if (uiT > 0.25) {
        uiT = 0;
        const v = d.vitals || {};
        const rec = G.lung;
        pp.stat('spo2', { value: String(Math.round((v.spo2 || 90) + (97 - (v.spo2 || 90)) * rec)), tone: rec > 0.6 ? 'teal' : (v.spo2 || 90) < 92 ? 'red' : '' });
        pp.stat('rr', { value: String(Math.round((v.rr || 24) - ((v.rr || 24) - 16) * rec)) });
        if (G.connected) sh.row('blood', ml0 ? `~${Math.max(0, Math.round(ml0 - G.drained))} mL` : '—', ml0 - G.drained > 300 ? 'amber' : 'teal');
      }
    }

    const api = {
      key(e) {
        if (G.done) { if (e.key === 'Enter') { pp.key(e); return true; } return false; }
        if (/^[1-9]$/.test(e.key)) { pick(e.key); return true; }
        const id = stepId();
        if (e.code === 'KeyN' && id === 'numb') { G.numbSkipped = true; G.score.numb = 0; sh.row('numb', T('pt_numb_skip', 'skipped'), 'red'); pp.flash('warn', T('cd_fl_skip', 'No local: the patient will feel this.'), 2400); nextStep(); return true; }
        if (e.key === ' ' && id === 'dissect' && G.popped && G.tool === 'clamp') {
          G.spread++;
          const t = S.tools.active;
          if (t && t.set) { t.set({ open: 1 }); setTimeout(() => t.set && t.set({ open: 0 }), 260); }
          if (G.wound) G.wound.set({ open: 2.4 + G.spread * 0.35 });
          NZA.audio.click(420);
          if (!G.numbed) flinch();
          return true;
        }
        if (e.key === 'Enter' && id === 'tube' && G.depth > 2) {
          G.tubeSet = true;
          G.score.tube = G.depth >= 10 && G.depth <= 14 ? 20 : (G.depth >= 8 && G.depth <= 16 ? 10 : 3);
          pp.flash(G.score.tube >= 20 ? 'ok' : 'warn', T('cd_fl_tube', 'Tube clamped at %s cm.', G.depth.toFixed(1)), 2400);
          nextStep();
          return true;
        }
        return false;
      },
      frame,
      msg: {
        vitals(v) { d.vitals = Object.assign(d.vitals || {}, v || {}); pp.stat('hr', { value: String(Math.round(v.hr || v.ecgRate || 0) || '--') }); },
        result(o) {
          G.done = true;
          const ok = !o.failed;
          dw.querySelector('.st').textContent = ok ? T('dr_done', 'secured') : T('dr_fail', 'no flow');
          pp.complete({ title: ok ? T('cd_res_t', 'Drain in · %s', o.grade || '-') : T('cd_res_fail', 'The tube is not in the chest'), text: o.msg || '', label: T('done', 'Done'), onDone: () => app.close() });
          pp.wide({ label: T('score', 'Score'), value: String(o.score ?? 0), unit: '', meter: { value: (o.score || 0) / 100, zone: [0.72, 1] }, caption: T('grade', 'grade %s', o.grade || '-'), captionTone: ok ? 'teal' : 'red' });
          NZA.audio[ok ? 'success' : 'fail']();
        },
      },
      destroy() { pp.destroy(); dw.remove(); if (ink) ink.dispose(); MS.dispose(); sh.destroy(); },
      _dbg: { S, G, target, cutLine: () => cutLine(), pick, connect, ribV, nextStep, placeMark, MS, hand, finger, pen },
    };
    return api;
  }

  /* ═════════════ NEEDLE DECOMPRESSION ═════════════ */
  function DecompressMode(app, d) {
    const side = d.side === 'left' ? 'left' : 'right';
    const tag = T('dc_tag', 'Needle decompression · %s side', T('side_' + side, side));
    const STEPS = [T('dc_s1', 'Find the 2nd rib space'), T('dc_s2', 'Push the needle in')];
    if (!window.NZA3D || !NZA3D.supported()) return Fallback(app, d, STEPS, tag, {});
    const sh = Shell(app, d, { sub: tag, scene: { region: 'chest', size: [0.6, 0.44], hair: 0.3, focus: { uv: [0.5, 0.6], size: [0.1, 0.1] } } });
    const S = sh.S;
    if (!S) { sh.destroy(); return Fallback(app, d, STEPS, tag, {}); }
    const THREE = window.THREE;
    const H = S.patch.H, W = S.patch.W;
    const med = side === 'right' ? 1 : -1;                       // the breastbone lies toward +u on the right side
    const SP = 0.024 / H;
    const clavV = u => 0.84 - 0.05 * (u - 0.5) * med;           // collarbone, rising toward the shoulder
    const ribV = (n, u) => 0.84 - 0.05 - (n - 1) * SP - 0.012 + 0.05 * (u - 0.5) * med;
    const mcl = 0.5;                                             // middle of the collarbone
    const target = [mcl, ribV(2, mcl) - SP / 2];
    const MS = meshes(S);
    const ink = Ink(S);
    for (let u = 0.06; u <= 0.95; u += 0.034) S.bumps.add({ uv: [u, clavV(u)], radius: 0.014, height: 0.0042 });
    S.bumps.add({ uv: [0.5 - 0.36 * med, clavV(0.5 - 0.36 * med) - 0.02], radius: 0.05, height: 0.004 });     // shoulder / chest muscle
    S.bumps.add({ uv: [0.5 - 0.06 * med, clavV(0.5) + 0.05], radius: 0.04, height: -0.0035 });                 // hollow above the collarbone
    for (let n = 2; n <= 6; n++) for (let u = 0.1; u <= 0.9; u += 0.036) { const v = ribV(n, u); if (v > 0.05) S.bumps.add({ uv: [u, v], radius: 0.013, height: 0.0016 }); }
    S.bumps.add({ uv: [0.5 + 0.42 * med, 0.5], radius: 0.06, height: -0.0016 });                              // groove over the breastbone
    S.bumps.add({ uv: [0.5 + 0.43 * med, clavV(0.5 + 0.43 * med) + 0.01], radius: 0.022, height: -0.003 });      // notch above the breastbone
    const nip = [0.5 - 0.02 * med, ribV(4, 0.5) - SP * 0.5];
    S.bumps.add({ uv: nip, radius: 0.0045, height: 0.0024 });
    if (ink) { ink.areola(nip, 0.014, d.tone !== undefined ? +d.tone : 0.35); ink.flush(); }
    S.controls.frame([0.5, 0.62], 0.3, { pitch: 1.14 });
    S.prewarm(['syringe'], false);
    MS.sheet();
    const hand = MS.hand('palpate');
    const pen = MS.pen();
    const G = { step: 0, mark: null, err: null, push: 0, popped: false, lmb: false, done: false, score: 0, t: 0, tool: 'hand', lens: 0 };
    const tlist = () => [
      { key: '1', label: T('cd_t_hand', 'Palpate'), icon: 'hand', state: G.step > 0 ? 'done' : G.tool === 'hand' ? 'active' : '' },
      { key: '2', label: T('cd_t_pen', 'Skin marker'), icon: 'edit', state: G.step > 0 ? 'done' : G.tool === 'pen' ? 'active' : '' },
      { key: '3', label: T('dc_t_needle', 'Needle'), icon: 'needle', state: G.step === 1 ? 'active' : 'locked' },
    ];
    const pp = NZA.ui.ProcPanel(sh.ppHost, {
      tag, step: 1, total: 2, steps: STEPS, title: STEPS[0],
      text: T('dc_x1', 'Feel the collarbone with {1} and count down the ribs. Mark the **2nd rib space** under the **middle of the collarbone** with {2}.'),
      wide: { label: T('cd_w_mark', 'Off target'), value: '--', unit: 'mm', meter: { value: 0, zone: [0, 0.2] } },
      stats: [{ id: 'spo2', label: 'SpO₂', value: String((d.vitals && d.vitals.spo2) || '--'), unit: '%' }, { id: 'sys', label: T('st_bp', 'Systolic'), value: String((d.vitals && d.vitals.sys) || '--') }],
      tools: tlist(),
      hints: [{ keys: [T('k_rmb', 'RMB')], label: T('h_look3', 'look around') }, { keys: [T('k_wheel', 'Wheel')], label: T('h_zoom', 'zoom') }],
      abort: { label: T('hold_stop_needle', 'Hold to stop'), key: 'ESC', seconds: 1.2 }, onAbort: () => app.abort(),
      onTool: k => pickTool(k),
    });
    sh.patient([
      { id: 'side', label: T('pt_side', 'Side'), value: T('side_' + side, side) },
      { id: 'air', label: T('pt_air', 'Air in chest'), value: d.tension === false ? T('pt_simple', 'simple') : T('pt_tension', 'tension'), tone: 'red' },
      { id: 'trachea', label: T('pt_trachea', 'Windpipe'), value: d.tension === false ? T('pt_mid', 'midline') : T('pt_shift', 'pushed away'), tone: d.tension === false ? '' : 'amber' },
    ]);
    function pickTool(k) {
      if (G.done) return;
      if (G.step === 0 && (k === '1' || k === '2')) {
        G.tool = k === '1' ? 'hand' : 'pen';
        S.tools.use(G.tool === 'hand' ? hand : pen);
        pp.set({ tools: tlist() });
        NZA.audio.click(640);
      }
    }
    S.tools.use(hand);
    S.on('down', e => {
      if (e.button !== 0 || G.done) return;
      G.lmb = true; S.tools.press(true);
      const hit = sh.hit();
      if (G.step === 0 && hit && G.tool === 'pen') {
        G.mark = hit.uv;
        if (ink) { ink.cross(hit.uv, 0.008, 0); ink.flush(); } else S.markers.set('mark', { uv: hit.uv, kind: 'cross', color: 0x5b2f9c, size: 0.007 });
        G.err = S.distanceUv(hit.uv, target) / MM;
        const tone = G.err <= 10 ? 'ok' : G.err <= 22 ? 'warn' : 'bad';
        pp.wide({ value: String(Math.round(G.err)), meter: { value: clamp(G.err / 50, 0, 1), zone: [0, 0.2], tone: tone === 'ok' ? '' : tone === 'warn' ? 'amber' : 'red' } });
        const tooMed = (hit.uv[0] - 0.5) * med > 0.12;
        pp.flash(tone, tooMed ? T('dc_fl_med', 'Too close to the breastbone: big vessels run there.') : tone === 'ok' ? T('dc_fl_ok', 'Right spot.') : T('dc_fl_off', '%s mm from the ideal spot.', Math.round(G.err)), 2600);
        G.score = (G.err <= 8 ? 55 : G.err <= 15 ? 45 : G.err <= 25 ? 30 : 12) - (tooMed ? 15 : 0);
        G.step = 1;
        setTimeout(() => {
          pp.set({ step: 2, title: STEPS[1], text: T('dc_x2', 'Hold {LMB} on the mark and push straight down, just over the top of the 3rd rib, until you hear the hiss.'), tools: tlist(), wide: { label: T('dc_w_push', 'Depth'), value: '0', unit: '%', meter: { value: 0, zone: [0.95, 1] } } });
          S.tools.use('syringe', { tilt: 0.12, yaw: 1.4 });
        }, 700);
      }
    });
    S.on('up', e => { if (e.button === 0) { G.lmb = false; S.tools.press(false); } });
    const curves = [{ cls: 'cl', pts: Array.from({ length: 22 }, (_, i) => { const u = 0.06 + i * 0.042; return [u, clavV(u)]; }) }];
    for (let n = 1; n <= 6; n++) curves.push({ cls: n === 2 || n === 3 ? 'rb hi' : 'rb', pts: Array.from({ length: 22 }, (_, i) => { const u = 0.06 + i * 0.042; return [u, ribV(n, u)]; }) });
    curves.push({ cls: 'mcl', pts: [[mcl, 0.92], [mcl, 0.3]] });
    const labels = [{ uv: [0.5 - 0.1 * med, clavV(0.5 - 0.1 * med) + 0.025], t: T('dc_clav_s', 'collarbone'), cls: 'hi' }];
    for (let n = 1; n <= 6; n++) labels.push({ uv: [0.5 - 0.12 * med, ribV(n, 0.5 - 0.12 * med) + 0.004], t: String(n), cls: n === 2 || n === 3 ? 'hi' : '' });
    labels.push({ uv: [mcl + 0.012, 0.36], t: T('dc_mcl', 'mid-clavicle'), cls: 'sp' });
    function frame(dt) {
      G.t += dt;
      const hit = sh.hit();
      let ring = null, txt = '', tone = '';
      const pressing = G.step === 0 && G.tool === 'hand' && G.lmb && hit;
      G.lens = clamp(G.lens + (pressing ? dt * 4 : -dt * 3), 0, 1);
      sh.svg.innerHTML = G.lens > 0 && sh.state.moved ? lensSVG(sh, sh.state.mouse.cx, sh.state.mouse.cy, 170, curves, labels, G.lens) : '';
      if (G.step === 0 && hit) {
        const v = hit.uv[1], u = hit.uv[0];
        const n = Math.round((ribV(1, u) - v) / SP + 1);
        txt = Math.abs(v - clavV(u)) < 0.03 ? T('dc_clav', 'collarbone') : (n >= 1 && n <= 7 ? (Math.abs(v - ribV(n, u)) < SP * 0.3 ? T('cd_rib', '%s rib', ORD(n)) : T('cd_space', '%s space', ORD(v > ribV(n, u) ? n - 1 : n))) : '');
        if (G.tool === 'hand') { ring = G.lmb && txt ? 1 : null; tone = txt === T('cd_space', '%s space', ORD(2)) ? 'teal' : ''; if (!G.lmb) txt = ''; }
        else { ring = txt ? 0 : null; tone = txt === T('cd_space', '%s space', ORD(2)) ? 'teal' : ''; }
      }
      if (G.step === 1 && !G.popped && G.lmb && hit && G.mark) {
        const near = S.distanceUv(hit.uv, G.mark) / MM < 7;
        if (near) {
          G.push = Math.min(1, G.push + dt / 1.8);
          ring = G.push; txt = `${Math.round(G.push * 100)}%`; tone = 'teal';
          if (G.push >= 1) {
            G.popped = true;
            NZA.audio.noise(1600, { vol: 0.12, lp: 4200, hp: 500, attack: 0.02, release: 0.7 });
            S.controls.shake(0.25, 300);
            S.layers.splat('wet', G.mark, 0.006, 0.6);
            pp.flash('ok', T('dc_fl_hiss', 'Hiss! Trapped air rushes out of the needle.'), 3000);
            sh.row('air', T('pt_released', 'released'), 'teal');
            sh.row('trachea', T('pt_mid', 'midline'), 'teal');
            G.score += 45;
            setTimeout(() => finish(), 1500);
          }
        } else { ring = G.push; txt = T('cd_on_mark', 'on the mark'); tone = 'amber'; }
        pp.wide({ value: String(Math.round(G.push * 100)), meter: { value: G.push, zone: [0.95, 1] } });
      }
      sh.ring(ring, txt, tone);
      if (G.popped) {
        const v = d.vitals || {};
        G.rec = Math.min(1, (G.rec || 0) + dt / 3);
        pp.stat('spo2', { value: String(Math.round((v.spo2 || 86) + (94 - (v.spo2 || 86)) * G.rec)), tone: 'teal' });
        pp.stat('sys', { value: String(Math.round((v.sys || 80) + (104 - (v.sys || 80)) * G.rec)), tone: 'teal' });
      }
    }
    function finish() {
      if (G.done) return;
      G.done = true;
      S.tools.use(null);
      app.post('finish', { result: { score: clamp(Math.round(G.score), 0, 100) } }).then(r => { if (r && r.outcome) api.msg.result(r.outcome); });
    }
    const api = {
      key(e) {
        if (G.done && e.key === 'Enter') { pp.key(e); return true; }
        if (e.key === '1' || e.key === '2') { pickTool(e.key); return true; }
        return false;
      },
      frame,
      msg: {
        result(o) {
          const ok = !o.failed;
          pp.complete({ title: ok ? T('dc_res_t', 'Air released · %s', o.grade || '-') : T('dc_res_fail', 'No air came out'), text: o.msg || '', label: T('done', 'Done'), onDone: () => app.close() });
          NZA.audio[ok ? 'success' : 'fail']();
        },
      },
      destroy() { pp.destroy(); if (ink) ink.dispose(); MS.dispose(); sh.destroy(); },
      _dbg: { S, G, target, hand, pen },
    };
    return api;
  }

  U.modes = Object.assign(U.modes || {}, { chestdrain: ChestDrainMode, decompress: DecompressMode });
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
      const qp = new URLSearchParams(location.search).get('q');
      if (qp) data.quality = qp;
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
      sc.add(new THREE.HemisphereLight(0xdfe8ee, 0x2a2420, 0.35));
      const key = new THREE.SpotLight(0xfff1e2, 1.15, 0, 0.6, 0.7, 1);
      key.position.set(0.35, 1.9, 0.25); key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0005;
      sc.add(key); sc.add(key.target);
      // trolley mattress + sheet
      const mat = new THREE.Mesh(new THREE.BoxGeometry(0.78, 0.12, 2.1), new THREE.MeshStandardMaterial({ color: new THREE.Color(0x2a3a44).convertSRGBToLinear(), roughness: 0.9 }));
      mat.position.set(0, -0.17, 0.05); mat.receiveShadow = true; sc.add(mat);
      const sheet = new THREE.Mesh(new THREE.PlaneGeometry(0.74, 2.0, 1, 1), new THREE.MeshStandardMaterial({ color: new THREE.Color(0x9fb0b8).convertSRGBToLinear(), roughness: 0.95 }));
      sheet.rotation.x = -Math.PI / 2; sheet.position.set(0, -0.108, 0.05); sheet.receiveShadow = true; sc.add(sheet);
      const floor = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), new THREE.MeshStandardMaterial({ color: 0x23292d, roughness: 1 }));
      floor.rotation.x = -Math.PI / 2; floor.position.y = -0.95; sc.add(floor);
      // torso (same parameterisation as the probe view)
      const prof = [[0.0, -0.36], [0.16, -0.35], [0.2, -0.27], [0.18, -0.12], [0.165, 0.0], [0.178, 0.12], [0.205, 0.24], [0.215, 0.3], [0.17, 0.35], [0.06, 0.38], [0.0, 0.385]].map(p => new THREE.Vector2(p[0], p[1]));
      const lg = new THREE.LatheGeometry(prof, 64);
      lg.rotateX(Math.PI / 2); lg.scale(1, 0.58, 1);
      const skin = new THREE.MeshStandardMaterial({ color: new THREE.Color(0xa0705a).convertSRGBToLinear(), roughness: 0.58, metalness: 0.0 });
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
      const dark = new THREE.MeshStandardMaterial({ color: new THREE.Color(0x5a3426).convertSRGBToLinear(), roughness: 0.6 });
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
      const camPos = new THREE.Vector3(-0.22, 1.12, -0.5), look = new THREE.Vector3(-0.22, 0, 0.05);
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
    const over = !!(e.target && e.target.closest && e.target.closest('.us-dev,.us-plan,.pp-col,.pp-card,.pp-belt,.pp-abort,.pp-read'));
    a.mode.overUi(over);
  });

  void app; void esc;
})();
