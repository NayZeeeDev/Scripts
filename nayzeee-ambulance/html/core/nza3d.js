/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · NZA3D — shared WebGL close-up engine            (suture module)
   Global: window.NZA3D. Needs window.THREE r149 (vendor/three.min.js). No ES modules.
   Used by: suture (owner), bullet, burn, ultrasound / chest drain.

   ───────────────────────────────────────────────────────────────────────────
   QUICK START
     const S = NZA3D.createScene(hostEl, { tone: 0.3, region: 'chest', sex: 'm',
                                           focus: { uv: [0.5, 0.5], size: [0.09, 0.03] } });
     const w = S.wounds.add({ type: 'laceration', uv: [0.5, 0.5], length: 0.056, gape: 0.004, depth: 0.007 });
     S.layers.splat('blood', w.at(0.5).uv, 0.006, 0.6);
     S.tools.use('saline');                 // tool follows the cursor on the skin
     S.on('frame', dt => { ... });          // your game loop (runs after the engine update)
     ...
     S.dispose();                           // frees every texture, geometry, material and target

   UNITS & SPACES
     metres everywhere (NZA3D.MM = 0.001). The skin is a patch W×H (S.patch.W/H) that lies on
     a base surface (flat, or a cylinder for limbs / torso). Patch coordinates:
       s ∈ [-W/2, W/2]  → screen right            u = s / W + 0.5
       t ∈ [-H/2, H/2]  → toward the viewer (down) v = 0.5 - t / H
     "uv" values are [u, v] arrays (or {x, y} / THREE.Vector2). Height above the base surface is
     the wound field (grooves, craters, blisters, bumps).

   createScene(container, opts) → S
     opts  tone 0..1 (0 very light → 1 dark) · region (NZA region name: 'chest', 'l_lower_arm'…)
           sex 'm'|'f' · seed · hair 0..1 (null = region/sex default) · size [W, H] (m)
           focus { uv:[u,v], size:[w,h] (m) } denser mesh where the work happens
           drape false | { radius (m), uv:[u,v], color } surgical drape with a round window
           quality 'high'|'medium'|'low' · exposure · keys (R recentre) · fullscreen (true)
           gravity [gs, gt] direction blood runs on the patch (default [0, 1] = toward viewer)
     S.renderer S.scene S.camera S.patch {W,H} S.canvas S.quality S.region S.shape {axis,R}
     S.on('frame'|'pointer'|'down'|'up'|'resize', fn) S.off(name, fn)   S.start() S.stop()
     S.step(dt, render = true)  advance one frame by hand (render false: simulate only)
     S.prewarm(toolNames?, withDressing = true)  compile tool / dressing shaders now (no hitch on first use)
     S.dispose()        stops, removes listeners and frees all GPU memory of this scene
                        (the WebGL context itself is pooled and reused by the next scene).
     S.pointer          last pointer { x, y } (canvas fractions 0..1), S.buttons (bitmask)

   CONTROLS  S.controls  right-drag look around, Shift+right-drag pan, wheel zoom, R recentre
     .frame(uv, width_m, { pitch, yaw })   aim at uv so width_m fills the view (sets the home view)
     .recenter() .shake(amount 0..1, ms) .set({ yaw, pitch, dist, target }) .enabled
     .limits = { yaw, pitchMin, pitchMax, distMin, distMax, pan }

   PICKING
     S.raycast(pointer) → { point (Vector3), normal (Vector3), uv [u,v], s, t, height } | null
                          pointer = MouseEvent | { x, y } canvas fractions (default S.pointer)
     S.surfaceAt(uv) → { point, normal, height }   S.project(uvOrVec3) → { x, y, visible }
     S.uvToST(uv) → [s, t]   S.stToUv(s, t) → [u, v]   S.heightAt(uv) → metres
     S.distanceUv(a, b) → metres along the patch

   SKIN LAYERS  S.layers   paintable masks (GPU render targets + CPU mirror for gameplay maths)
     names: blood grime iodine soot bruise wet clot eschar
     .paint(name, uv, radius_m | [rx, ry], amount, { hardness 0..1, grain 0..1, grainScale, angle, mode 'add'|'erase' })
     .stroke(name, uvA, uvB, radius, amount, opts)   stamps along a segment
     .splat(name, uv, radius, amount, opts)          organic blob (many stamps)
     .erase(name, uv, radius, amount, opts)          = paint(..., mode 'erase')
     .fill(name, value)  .clear(name)  .decay(name, perSecond)  (continuous fade, 0 = stop)
     .sample(name, uv) → 0..1   .average(name, uv, radius_m) → 0..1
     .coverage(name, uv, radius_m, threshold) → 0..1   .total(name, uv?, radius_m?) → Σ cells
     .mask(uv, radius_m) → helper object for repeated area queries

   WOUNDS  S.wounds  (rendered into a height/colour field, also used for raycasts)
     .add(def) → wound      .remove(wound)   .list   .clear()
       def.type 'laceration' | 'stab' | 'incision' | 'gunshot' | 'burn'
       line wounds: uv (centre) angle (rad, 0 = screen right) length (m) curve (m) wobble 0..1
                    points [[u,v]…] (overrides) gape (m) depth (m) jagged 0..1 rim 0..1
                    rimWidth (m) swell (m) taper (end sharpness) cut 0..1 open 0..1 seed
       gunshot:     uv radius (m) ring (abrasion collar, m) depth jagged open
       burn:        uv radius | [rx, ry] (m) degree 1..3 irregular 0..1 blisters (count)
     wound.set(patch) · wound.at(tN) → { uv, s, t, dir:[ds,dt], nrm:[ns,nt] }
     wound.halfGape(tN) (m) · wound.edge(tN, side ±1, offset_m) → uv · wound.locate(uv) → { d, tN, side, L }
     wound.close(tN, amount 0..1, sigmaN) · wound.closure (Float32Array per point) · wound.length (m)
     wound.blisters (burn: bump handles) · wound.remove()
   BUMPS   S.bumps.add({ uv, radius, height }) → { set({radius,height,uv}), remove() }   (blebs, dimples)

   FLUIDS  S.fluids
     .jet({ on, from: Vector3, to: Vector3 | hit, wash: { grime: 1, blood: .6, soot: .5 }, wet: 1, rate })
          saline stream (core + particles + splashes); it washes the layers it hits.
          .jet(false) stops. .onImpact(fn(hit, dt)) per-frame callback while the jet hits skin.
     .bleed(wound, mlPerMin) ooze from a wound (pools in the groove, overflows as rivulets)
     .drip(uv, volume)  one rivulet   .drops(point, count, color)  burst of droplets   .clear()

   TOOLS  S.tools   meshes: saline (bottle) irrigator (30 mL syringe) syringe (5 mL) probe needleDriver forceps
                    scalpel gauze stapler dermatome
     .use(name | null, poseOpts) → tool  (follows the cursor: lift, pressLift, tilt, yaw, roll)
     .active  .get(name)  .press(bool)  .hover(bool)  .follow (true)  .hit (last raycast)
     tool.group (THREE.Group, tip at origin, handle along +Y) tool.set({ plunger, open, squeeze, stain })
     tool.tipWorld() → Vector3     tool.pose (current pose options, mutable)

   MARKERS  S.markers.set(id, { uv, kind 'ring'|'dashed'|'dot'|'check'|'cross'|'pin', color, size, opacity, pulse })
            .remove(id)  .clear()  .get(id)

   STITCHES S.stitches.add({ a: uv, b: uv, knot 'a'|'b', color, radius }) → { remove() }
            .preview(aUv, toPoint Vector3 | uv | null)   live thread while pulling   .clear() .list

   DRESSING S.dressing.create({ size:[w,h], pad:[pw,ph], uv, angle }) → D
            D.pick(hit) → 'edge' | 'body' | null   D.grab(hit) → bool   D.move(hit)   D.release()
            D.rub(hit, dt) presses and sticks · D.stuck 0..1 · D.state 'rest'|'carried'|'falling'|'placed'
            D.covers(uvList) → fraction under the pad · D.seep(amount 0..1) · D.remove()

   STATIC   NZA3D.supported() → bool   NZA3D.MM   NZA3D.release() (drop the pooled WebGL context)
            NZA3D.tones (skin palette)  NZA3D.util { rng, clamp, lerp, smooth }
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const THREE = window.THREE;
  const MM = 0.001;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const TAU = Math.PI * 2;

  function rng(seed) {
    let a = (seed >>> 0) || 0x9e3779b9;
    return () => {
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function hashStr(s) {
    let h = 2166136261;
    s = String(s);
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
  }
  const gauss = r => { let u = 0; for (let i = 0; i < 4; i++) u += r(); return (u - 2) / 0.577; };
  const canvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
  const uvOf = p => (Array.isArray(p) ? p : p && p.x !== undefined ? [p.x, p.y] : p && p.uv ? uvOf(p.uv) : [0.5, 0.5]);

  /* ─────────────────────────── shared tileable noise ───────────────────────────
     256² RGBA, every channel tiles:
       R  fbm (5 octaves, base period 4)     G  fbm (4 octaves, base period 6, other seed)
       B  worley F1 (8×8 cells, 0 at the feature points)    A  white noise
     The same data feeds tNoise on the GPU and noiseAt() on the CPU so both agree. */
  const NOISE_N = 256;
  let NOISE = null;
  function buildNoise() {
    if (NOISE) return NOISE;
    const N = NOISE_N, out = new Float32Array(N * N * 4), r = rng(90210);
    const fbm = (period, oct, gain, ch) => {
      const acc = new Float32Array(N * N);
      let amp = 1;
      for (let o = 0; o < oct; o++) {
        const P = period << o, g = new Float32Array(P * P);
        for (let i = 0; i < g.length; i++) g[i] = r();
        for (let y = 0; y < N; y++) {
          const fy = (y / N) * P, iy = Math.floor(fy), ty = fy - iy, sy = ty * ty * (3 - 2 * ty);
          const y0 = (iy % P) * P, y1 = ((iy + 1) % P) * P;
          for (let x = 0; x < N; x++) {
            const fx = (x / N) * P, ix = Math.floor(fx), tx = fx - ix, sx = tx * tx * (3 - 2 * tx);
            const x0 = ix % P, x1 = (ix + 1) % P;
            const a = g[y0 + x0] + (g[y0 + x1] - g[y0 + x0]) * sx;
            const b = g[y1 + x0] + (g[y1 + x1] - g[y1 + x0]) * sx;
            acc[y * N + x] += (a + (b - a) * sy) * amp;
          }
        }
        amp *= gain;
      }
      let lo = Infinity, hi = -Infinity;
      for (let i = 0; i < acc.length; i++) { if (acc[i] < lo) lo = acc[i]; if (acc[i] > hi) hi = acc[i]; }
      for (let i = 0; i < acc.length; i++) out[i * 4 + ch] = (acc[i] - lo) / (hi - lo || 1);
    };
    fbm(4, 5, 0.5, 0);
    fbm(6, 4, 0.55, 1);
    // worley
    const C = 8, cs = N / C, pts = [];
    for (let j = 0; j < C; j++) for (let i = 0; i < C; i++) pts.push([(i + 0.15 + r() * 0.7) * cs, (j + 0.15 + r() * 0.7) * cs]);
    for (let y = 0; y < N; y++) {
      const cy = Math.floor(y / cs);
      for (let x = 0; x < N; x++) {
        const cx = Math.floor(x / cs);
        let best = 1e9;
        for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
          const ci = (cx + di + C) % C, cj = (cy + dj + C) % C, p = pts[cj * C + ci];
          const px = p[0] + (cx + di - ((cx + di + C) % C)) * cs, py = p[1] + (cy + dj - ((cy + dj + C) % C)) * cs;
          const d = (px - x) * (px - x) + (py - y) * (py - y);
          if (d < best) best = d;
        }
        out[(y * N + x) * 4 + 2] = clamp(Math.sqrt(best) / (cs * 0.75), 0, 1);
      }
    }
    for (let i = 0; i < N * N; i++) out[i * 4 + 3] = r();
    NOISE = out;
    return out;
  }
  // bilinear, wrapping; u/v in tile units (1 = one tile)
  function noiseAt(ch, u, v) {
    const N = NOISE_N, d = NOISE || buildNoise();
    const fx = (u - Math.floor(u)) * N, fy = (v - Math.floor(v)) * N;
    const x0 = Math.floor(fx) % N, y0 = Math.floor(fy) % N, x1 = (x0 + 1) % N, y1 = (y0 + 1) % N;
    const tx = fx - Math.floor(fx), ty = fy - Math.floor(fy);
    const a = d[(y0 * N + x0) * 4 + ch], b = d[(y0 * N + x1) * 4 + ch];
    const c = d[(y1 * N + x0) * 4 + ch], e = d[(y1 * N + x1) * 4 + ch];
    return (a + (b - a) * tx) + ((c + (e - c) * tx) - (a + (b - a) * tx)) * ty;
  }

  /* ─────────────────────────── skin tones ─────────────────────────── */
  const TONES = [
    [0.00, [246, 219, 204]], [0.18, [239, 199, 176]], [0.36, [224, 172, 141]],
    [0.55, [190, 131, 98]], [0.75, [138, 90, 65]], [1.00, [86, 56, 42]],
  ];
  function toneRGB(t) {
    t = clamp(+t || 0, 0, 1);
    for (let i = 1; i < TONES.length; i++) {
      if (t <= TONES[i][0]) {
        const a = TONES[i - 1], b = TONES[i], k = (t - a[0]) / (b[0] - a[0]);
        return [lerp(a[1][0], b[1][0], k), lerp(a[1][1], b[1][1], k), lerp(a[1][2], b[1][2], k)];
      }
    }
    return TONES[TONES.length - 1][1].slice();
  }
  const rgba = (c, a = 1) => `rgba(${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])},${a})`;

  /* ─────────────────────────── texture generators (CPU canvases, cached) ─────────────────────────── */
  const texCache = new Map();
  function cached(key, fn) {
    if (texCache.has(key)) return texCache.get(key);
    const v = fn();
    texCache.set(key, v);
    if (texCache.size > 24) texCache.delete(texCache.keys().next().value);
    return v;
  }

  // Large non-tiling skin colour map: tone, mottling, redness, veins, freckles, moles.
  function makeSkinMacro(o) {
    return cached(`macro:${o.w}x${o.h}:${o.tone.toFixed(3)}:${o.seed}:${o.freckles}:${o.veins}:${o.W.toFixed(3)}`, () => {
      const { w, h } = o, cv = canvas(w, h), c = cv.getContext('2d'), R = rng(o.seed * 7 + 3);
      const base = toneRGB(o.tone), dark = o.tone;
      c.fillStyle = rgba(base); c.fillRect(0, 0, w, h);
      const pxPerM = w / o.W;
      const octave = (cellsM, alpha, mode, tint) => {
        const cw = Math.max(2, Math.round(o.W * cellsM)), ch = Math.max(2, Math.round(cw * h / w));
        const s = canvas(cw, ch), sc = s.getContext('2d'), id = sc.createImageData(cw, ch);
        for (let i = 0; i < cw * ch; i++) {
          const v = R() * 2 - 1;
          id.data[i * 4] = 128 + v * tint[0]; id.data[i * 4 + 1] = 128 + v * tint[1];
          id.data[i * 4 + 2] = 128 + v * tint[2]; id.data[i * 4 + 3] = 255;
        }
        sc.putImageData(id, 0, 0);
        c.save();
        c.globalAlpha = alpha; c.globalCompositeOperation = mode;
        c.imageSmoothingEnabled = true; c.imageSmoothingQuality = 'high';
        c.filter = `blur(${Math.max(0.6, (w / cw) * 0.55).toFixed(1)}px)`;
        c.drawImage(s, -w * 0.05, -h * 0.05, w * 1.1, h * 1.1);
        c.restore();
      };
      octave(9, 0.7, 'soft-light', [74, 50, 42]);       // ~11 cm blotches, warm/cool
      octave(26, 0.55, 'soft-light', [64, 32, 26]);      // capillary redness
      octave(70, 0.4, 'soft-light', [44, 36, 32]);
      octave(190, 0.22, 'soft-light', [36, 32, 30]);     // ~5 mm mottling
      octave(520, 0.16, 'soft-light', [30, 28, 28]);     // ~2 mm speckle
      // redness patches
      for (let i = 0; i < 14; i++) {
        const x = R() * w, y = R() * h, r = (0.015 + R() * 0.05) * pxPerM;
        const g = c.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, `rgba(200,80,70,${0.05 + R() * 0.06})`); g.addColorStop(1, 'rgba(200,80,70,0)');
        c.fillStyle = g; c.fillRect(x - r, y - r, r * 2, r * 2);
      }
      // veins (light skin, limbs & chest)
      if (o.veins > 0 && dark < 0.65) {
        c.save();
        c.filter = `blur(${(0.0016 * pxPerM).toFixed(1)}px)`;
        c.lineCap = 'round';
        const n = Math.round(3 + o.veins * 5);
        for (let i = 0; i < n; i++) {
          let x = R() * w, y = R() * h, a = (R() - 0.5) * 0.8 + (o.veinAngle || 0);
          c.strokeStyle = `rgba(70,95,140,${(0.05 + R() * 0.06) * o.veins * (1 - dark)})`;
          c.lineWidth = (0.0014 + R() * 0.0022) * pxPerM;
          c.beginPath(); c.moveTo(x, y);
          const seg = 6 + Math.floor(R() * 6);
          for (let k = 0; k < seg; k++) {
            a += (R() - 0.5) * 0.7;
            const L = (0.008 + R() * 0.018) * pxPerM;
            const nx = x + Math.cos(a) * L, ny = y + Math.sin(a) * L;
            c.quadraticCurveTo((x + nx) / 2 + (R() - 0.5) * L * 0.5, (y + ny) / 2 + (R() - 0.5) * L * 0.5, nx, ny);
            x = nx; y = ny;
          }
          c.stroke();
        }
        c.restore();
      }
      // freckles (clustered) & moles
      const fr = Math.round(o.freckles * (1 - dark * 0.6) * o.W * o.H * 9000);
      const pig = [base[0] * 0.62, base[1] * 0.46, base[2] * 0.36];
      c.save();
      c.filter = `blur(${(0.00018 * pxPerM).toFixed(2)}px)`;
      for (let i = 0; i < fr; i++) {
        const x = R() * w, y = R() * h;
        if (noiseAt(0, x / w * 2, y / h * 2 * h / w) < 0.48) continue;
        const r = (0.00018 + R() * R() * 0.0009) * pxPerM;
        c.fillStyle = rgba(pig, 0.12 + R() * 0.32);
        c.beginPath(); c.ellipse(x, y, r * (0.8 + R() * 0.5), r, R() * 3, 0, TAU); c.fill();
      }
      c.restore();
      const moles = Math.floor(R() * 3);
      for (let i = 0; i < moles; i++) {
        const x = (0.15 + R() * 0.7) * w, y = (0.15 + R() * 0.7) * h, r = (0.0012 + R() * 0.0014) * pxPerM;
        const g = c.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, rgba([pig[0] * 0.55, pig[1] * 0.5, pig[2] * 0.5], 0.85));
        g.addColorStop(0.7, rgba([pig[0] * 0.7, pig[1] * 0.62, pig[2] * 0.6], 0.6));
        g.addColorStop(1, rgba(pig, 0));
        c.fillStyle = g; c.beginPath(); c.arc(x, y, r, 0, TAU); c.fill();
      }
      // fine grain
      const id = c.getImageData(0, 0, w, h), d = id.data;
      for (let i = 0; i < d.length; i += 4) {
        const v = (R() - 0.5) * 7;
        d[i] = d[i] + v; d[i + 1] = d[i + 1] + v * 0.9; d[i + 2] = d[i + 2] + v * 0.85;
      }
      c.putImageData(id, 0, 0);
      return cv;
    });
  }

  // height (Float32, 0..1) → tangent-space normal map RGBA bytes, wrapping
  function heightToNormal(hgt, N, strength) {
    const out = new Uint8ClampedArray(N * N * 4);
    for (let y = 0; y < N; y++) {
      const ym = ((y - 1 + N) % N) * N, yp = ((y + 1) % N) * N, yc = y * N;
      for (let x = 0; x < N; x++) {
        const xm = (x - 1 + N) % N, xp = (x + 1) % N;
        const dx = (hgt[yc + xp] - hgt[yc + xm]) * strength;
        const dy = (hgt[yp + x] - hgt[ym + x]) * strength;
        // canvas rows go down, texture v goes up → flip dy
        const nx = -dx, ny = dy, nz = 1, l = Math.hypot(nx, ny, nz);
        const i = (yc + x) * 4;
        out[i] = (nx / l * 0.5 + 0.5) * 255; out[i + 1] = (ny / l * 0.5 + 0.5) * 255; out[i + 2] = (nz / l * 0.5 + 0.5) * 255; out[i + 3] = 255;
      }
    }
    return out;
  }

  // Tiling micro detail (one tile ≈ o.tile metres): furrow network, pores, hair.
  // returns { normal: canvas (RGB normal), detail: canvas (R cavity, G hair, B roughness var, A 255) }
  function makeSkinMicro(o) {
    return cached(`micro:${o.seed}:${o.hairAngle.toFixed(2)}:${o.hairCount}:${o.hairLen}`, () => {
      const N = 512, R = rng(o.seed * 13 + 5);
      const hgt = new Float32Array(N * N), cav = new Float32Array(N * N);
      // furrows: worley F2-F1 over jittered cells (≈0.5 mm)
      const C = 52, cs = N / C, pts = new Float32Array(C * C * 2);
      for (let j = 0; j < C; j++) for (let i = 0; i < C; i++) {
        pts[(j * C + i) * 2] = (i + 0.1 + R() * 0.8) * cs; pts[(j * C + i) * 2 + 1] = (j + 0.1 + R() * 0.8) * cs;
      }
      const poreAt = new Float32Array(C * C), edgeW = new Float32Array(C * C);
      for (let i = 0; i < poreAt.length; i++) { poreAt[i] = R() < 0.3 ? 0.9 + R() * 1.3 : 0; edgeW[i] = 0.25 + R() * 0.75; }
      for (let y = 0; y < N; y++) {
        const cy = Math.floor(y / cs);
        for (let x = 0; x < N; x++) {
          const cx = Math.floor(x / cs);
          let f1 = 1e9, f2 = 1e9, id1 = 0, id2 = 0;
          for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
            const ci = (cx + di + C) % C, cj = (cy + dj + C) % C, k = cj * C + ci;
            const px = pts[k * 2] + (cx + di - ci) * cs, py = pts[k * 2 + 1] + (cy + dj - cj) * cs;
            const d = (px - x) * (px - x) + (py - y) * (py - y);
            if (d < f1) { f2 = f1; id2 = id1; f1 = d; id1 = k; } else if (d < f2) { f2 = d; id2 = k; }
          }
          const e = Math.sqrt(f2) - Math.sqrt(f1);
          const major = noiseAt(1, x / N * 3, y / N * 3);
          const ew = Math.min(edgeW[id1], edgeW[id2]) * (0.55 + major * 0.9);
          const furrow = (1 - smooth(0, 0.8 + ew * 1.6, e)) * ew;
          const pr = Math.sqrt(f1);
          const pore = poreAt[id1] ? 1 - smooth(poreAt[id1] * 0.45, poreAt[id1] * 1.25, pr) : 0;
          const fine = noiseAt(0, x / N * 8, y / N * 8) * 0.5 + noiseAt(1, x / N * 16, y / N * 16) * 0.5;
          const i = y * N + x;
          hgt[i] = 1 - furrow * 0.42 - pore * 0.75 + fine * 0.45;
          cav[i] = clamp(furrow * 0.4 + pore * 0.85, 0, 1);
        }
      }
      const normal = canvas(N, N);
      normal.getContext('2d').putImageData(new ImageData(heightToNormal(hgt, N, 1.15), N, N), 0, 0);
      // hair: wrapped strokes on a separate canvas
      const hair = canvas(N, N), hc = hair.getContext('2d');
      hc.fillStyle = '#000'; hc.fillRect(0, 0, N, N);
      hc.lineCap = 'round';
      const pxPerM = N / o.tile;
      for (let k = 0; k < o.hairCount; k++) {
        const x = R() * N, y = R() * N, a = o.hairAngle + gauss(R) * 0.45;
        const L = (o.hairLen * (0.4 + R() * 0.8)) * pxPerM;
        const bend = (R() - 0.5) * 0.9 * L;
        const ex = x + Math.cos(a) * L, ey = y - Math.sin(a) * L;
        const mx = (x + ex) / 2 - Math.sin(a) * bend, my = (y + ey) / 2 - Math.cos(a) * bend;
        // most body hair is fine and pale (vellus); a few are terminal hairs
        const terminal = R() < 0.35;
        const width = terminal ? 0.9 + R() * 0.5 : 0.5 + R() * 0.35, alpha = terminal ? 0.65 + R() * 0.3 : 0.28 + R() * 0.25;
        hc.fillStyle = `rgba(255,255,255,${(alpha * 0.6).toFixed(2)})`;
        for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) { hc.beginPath(); hc.arc(x + ox * N, y + oy * N, width * 0.75, 0, TAU); hc.fill(); }
        for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
          const dx = ox * N, dy = oy * N;
          for (let s = 0; s < 3; s++) {
            const t0 = s / 3, t1 = (s + 1) / 3;
            const P = t => [(1 - t) * (1 - t) * x + 2 * (1 - t) * t * mx + t * t * ex, (1 - t) * (1 - t) * y + 2 * (1 - t) * t * my + t * t * ey];
            const a0 = P(t0), a1 = P(t1);
            hc.strokeStyle = `rgba(255,255,255,${alpha * (1 - s * 0.22)})`;
            hc.lineWidth = width * (1 - s * 0.32);
            hc.beginPath(); hc.moveTo(a0[0] + dx, a0[1] + dy); hc.lineTo(a1[0] + dx, a1[1] + dy); hc.stroke();
          }
        }
      }
      const hd = hair.getContext('2d').getImageData(0, 0, N, N).data;
      const detail = canvas(N, N), dc = detail.getContext('2d'), dd = dc.createImageData(N, N);
      for (let i = 0; i < N * N; i++) {
        const y = Math.floor(i / N), x = i - y * N;
        dd.data[i * 4] = cav[i] * 255;
        dd.data[i * 4 + 1] = hd[i * 4];
        dd.data[i * 4 + 2] = noiseAt(1, x / N * 6, y / N * 6) * 255;
        dd.data[i * 4 + 3] = 255;
      }
      dc.putImageData(dd, 0, 0);
      return { normal, detail };
    });
  }

  // Plain-weave fabric tile (drape / gauze): { normal, albedo (grey 0..255 variation) }
  function makeWeave(o) {
    return cached(`weave:${o.threads}:${o.seed}:${o.fuzz}`, () => {
      const N = 256, R = rng(o.seed), T = o.threads, p = N / T;
      const hgt = new Float32Array(N * N);
      const alb = canvas(N, N), ac = alb.getContext('2d'), ad = ac.createImageData(N, N);
      const jit = new Float32Array(T * 2);
      for (let i = 0; i < jit.length; i++) jit[i] = R();
      for (let y = 0; y < N; y++) {
        for (let x = 0; x < N; x++) {
          const cx = Math.floor(x / p), cy = Math.floor(y / p);
          const fx = (x % p) / p, fy = (y % p) / p;
          const warpTop = (cx + cy) % 2 === 0;
          const warp = Math.sin(Math.PI * fx) * (0.85 + jit[cx % T] * 0.3);
          const weft = Math.sin(Math.PI * fy) * (0.85 + jit[T + (cy % T)] * 0.3);
          const along = warpTop ? Math.sin(Math.PI * fy) : Math.sin(Math.PI * fx);
          let h = warpTop ? warp * (0.6 + 0.4 * along) : weft * (0.6 + 0.4 * along);
          h += (noiseAt(3, x / N * 1.0, y / N * 1.0) - 0.5) * o.fuzz;
          hgt[y * N + x] = h;
          const v = 200 + (h - 0.5) * 70 + (R() - 0.5) * 18;
          const i = (y * N + x) * 4;
          ad.data[i] = v; ad.data[i + 1] = v; ad.data[i + 2] = v; ad.data[i + 3] = 255;
        }
      }
      ac.putImageData(ad, 0, 0);
      const normal = canvas(N, N);
      normal.getContext('2d').putImageData(new ImageData(heightToNormal(hgt, N, 3.0), N, N), 0, 0);
      return { normal, albedo: alb };
    });
  }

  // Non-woven sheet (dressing border) + absorbent pad + print. Returns a canvas (w×h px).
  function makeDressingTex(wM, hM, padW, padH, seed) {
    return cached(`dressing:${wM}:${hM}:${padW}:${padH}:${seed}`, () => {
      const pxm = 9000, w = Math.round(wM * pxm), h = Math.round(hM * pxm);
      const cv = canvas(w, h), c = cv.getContext('2d'), R = rng(seed);
      c.fillStyle = '#efede7'; c.fillRect(0, 0, w, h);
      // fibres
      c.lineCap = 'round';
      for (let i = 0; i < w * h / 55; i++) {
        const x = R() * w, y = R() * h, a = R() * TAU, L = 3 + R() * 9;
        c.strokeStyle = `rgba(${R() < 0.5 ? '255,255,255' : '180,176,168'},${0.18 + R() * 0.25})`;
        c.lineWidth = 0.5 + R() * 0.6;
        c.beginPath(); c.moveTo(x, y); c.lineTo(x + Math.cos(a) * L, y + Math.sin(a) * L); c.stroke();
      }
      // perforation dots on the adhesive border
      c.fillStyle = 'rgba(150,146,138,.18)';
      for (let y = 6; y < h; y += 11) for (let x = 6 + ((y / 11) % 2) * 5.5; x < w; x += 11) { c.beginPath(); c.arc(x, y, 0.9, 0, TAU); c.fill(); }
      // pad
      const pw = padW * pxm, ph = padH * pxm, px = (w - pw) / 2, py = (h - ph) / 2;
      c.save();
      c.shadowColor = 'rgba(0,0,0,.18)'; c.shadowBlur = 10;
      c.fillStyle = '#fbfbf8';
      const rr = 14;
      c.beginPath(); c.roundRect ? c.roundRect(px, py, pw, ph, rr) : c.rect(px, py, pw, ph); c.fill();
      c.restore();
      c.save();
      c.beginPath(); c.roundRect ? c.roundRect(px, py, pw, ph, rr) : c.rect(px, py, pw, ph); c.clip();
      c.strokeStyle = 'rgba(190,196,198,.35)'; c.lineWidth = 1;
      for (let k = -ph; k < pw + ph; k += 16) {
        c.beginPath(); c.moveTo(px + k, py); c.lineTo(px + k + ph, py + ph); c.stroke();
        c.beginPath(); c.moveTo(px + k + ph, py); c.lineTo(px + k, py + ph); c.stroke();
      }
      for (let i = 0; i < pw * ph / 40; i++) {
        c.fillStyle = `rgba(${R() < 0.5 ? '255,255,255' : '205,205,200'},${0.25 + R() * 0.3})`;
        c.fillRect(px + R() * pw, py + R() * ph, 1.2, 1.2);
      }
      c.restore();
      // brand print in a corner of the border
      const bx = w - 16, by = h - 13;
      c.save();
      c.font = '600 11px Lexend, sans-serif'; c.textAlign = 'right'; c.textBaseline = 'middle';
      c.fillStyle = 'rgba(80,90,92,.55)';
      c.fillText('NAYZEEE · STERILE', bx - 16, by);
      drawMark(c, bx - 11, by - 6, 12);
      c.restore();
      return cv;
    });
  }

  // NAYZEEE mark (teal chamfered tile with the inner bar) on a 2D canvas
  function drawMark(c, x, y, s) {
    const g = c.createLinearGradient(x, y, x + s, y + s);
    g.addColorStop(0, '#0fd4c4'); g.addColorStop(1, '#067d74');
    c.fillStyle = g;
    c.beginPath();
    c.moveTo(x, y); c.lineTo(x + s, y); c.lineTo(x + s, y + s * 0.56); c.lineTo(x + s * 0.56, y + s); c.lineTo(x, y + s); c.closePath();
    c.fill();
    c.fillStyle = 'rgba(0,0,0,.85)';
    c.fillRect(x + s * 0.22, y + s * 0.22, s * 0.56, s * 0.22);
  }

  // printed label for bottles / syringes
  function makeLabel(kind) {
    return cached(`label:${kind}`, () => {
      const w = 512, h = 256, cv = canvas(w, h), c = cv.getContext('2d');
      if (kind === 'saline') {
        c.fillStyle = '#f4f6f6'; c.fillRect(0, 0, w, h);
        c.fillStyle = '#0a8f85'; c.fillRect(0, 0, w, 34); c.fillRect(0, h - 22, w, 22);
        drawMark(c, 22, 64, 54);
        c.fillStyle = '#16191b'; c.font = '700 54px Lexend, sans-serif'; c.textBaseline = 'alphabetic';
        c.fillText('NaCl 0.9%', 96, 112);
        c.font = '500 25px Lexend, sans-serif'; c.fillStyle = '#3c4246';
        c.fillText('Sterile saline · irrigation', 98, 150);
        c.font = '600 22px "JetBrains Mono", monospace'; c.fillStyle = '#0a8f85';
        c.fillText('250 mL', 98, 190);
        c.fillStyle = 'rgba(0,0,0,.55)'; c.font = '600 15px Lexend, sans-serif';
        c.fillText('NAYZEEE MEDICAL', 22, 230);
        c.fillStyle = '#fff'; c.font = '700 16px Lexend, sans-serif'; c.fillText('FOR EXTERNAL USE', 22, 23);
      } else if (kind === 'syringe') {
        c.clearRect(0, 0, w, h);
        c.strokeStyle = 'rgba(20,24,26,.9)'; c.fillStyle = 'rgba(20,24,26,.9)';
        c.font = '600 18px Lexend, sans-serif'; c.textBaseline = 'middle';
        for (let i = 0; i <= 50; i++) {
          const x = 40 + i * 8.6, big = i % 10 === 0, mid = i % 5 === 0;
          c.lineWidth = big ? 2.2 : 1.3;
          c.beginPath(); c.moveTo(x, 40); c.lineTo(x, 40 + (big ? 46 : mid ? 32 : 20)); c.stroke();
          if (big) c.fillText(String(i / 10), x - 5, 112);
        }
        c.fillStyle = 'rgba(8,143,133,.95)'; c.font = '700 20px Lexend, sans-serif';
        c.fillText('LIDOCAINE 2%', 46, 170);
        c.fillStyle = 'rgba(20,24,26,.7)'; c.font = '500 15px Lexend, sans-serif'; c.fillText('5 mL · NAYZEEE', 46, 200);
      } else if (kind === 'irrigator') {
        c.clearRect(0, 0, w, h);
        c.strokeStyle = 'rgba(20,24,26,.88)'; c.fillStyle = 'rgba(20,24,26,.88)';
        c.font = '600 17px Lexend, sans-serif'; c.textBaseline = 'middle';
        for (let i = 0; i <= 30; i++) {
          const x = 30 + i * 14.6, big = i % 10 === 0, mid = i % 5 === 0;
          c.lineWidth = big ? 2.4 : 1.4;
          c.beginPath(); c.moveTo(x, 34); c.lineTo(x, 34 + (big ? 44 : mid ? 30 : 18)); c.stroke();
          if (big) c.fillText(String(i), x - (i >= 10 ? 9 : 5), 100);
        }
        c.fillStyle = 'rgba(8,143,133,.95)'; c.font = '700 22px Lexend, sans-serif';
        c.fillText('NaCl 0.9%', 34, 156);
        c.fillStyle = 'rgba(20,24,26,.7)'; c.font = '500 15px Lexend, sans-serif'; c.fillText('IRRIGATION · 30 mL · NAYZEEE', 34, 186);
        drawMark(c, 34, 206, 22);
      } else if (kind === 'stapler') {
        c.fillStyle = '#e9edee'; c.fillRect(0, 0, w, h);
        drawMark(c, 30, 90, 70);
        c.fillStyle = '#16191b'; c.font = '700 44px Lexend, sans-serif'; c.textBaseline = 'middle';
        c.fillText('NAYZEEE', 120, 112); c.font = '500 26px Lexend, sans-serif'; c.fillStyle = '#4a5155';
        c.fillText('SKIN STAPLER 35W', 120, 160);
      }
      return cv;
    });
  }

  // marker sprites (white, tinted by material colour)
  function makeMarkerSprite(kind) {
    return cached(`marker:${kind}`, () => {
      const N = 256, cv = canvas(N, N), c = cv.getContext('2d'), m = N / 2;
      c.strokeStyle = '#fff'; c.fillStyle = '#fff'; c.lineCap = 'round';
      const glow = (r, w) => { const g = c.createRadialGradient(m, m, r - w * 2, m, m, r + w * 2.4); g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.5, 'rgba(255,255,255,.35)'); g.addColorStop(1, 'rgba(255,255,255,0)'); c.fillStyle = g; c.fillRect(0, 0, N, N); c.fillStyle = '#fff'; };
      if (kind === 'ring' || kind === 'check' || kind === 'cross') {
        glow(96, 10); c.lineWidth = 14; c.beginPath(); c.arc(m, m, 96, 0, TAU); c.stroke();
        if (kind === 'check') { c.lineWidth = 18; c.beginPath(); c.moveTo(m - 40, m + 2); c.lineTo(m - 10, m + 32); c.lineTo(m + 44, m - 30); c.stroke(); }
        if (kind === 'cross') { c.lineWidth = 14; c.beginPath(); c.moveTo(m - 34, m - 34); c.lineTo(m + 34, m + 34); c.moveTo(m + 34, m - 34); c.lineTo(m - 34, m + 34); c.stroke(); }
      } else if (kind === 'dashed') {
        c.lineWidth = 11;
        for (let i = 0; i < 16; i++) { c.beginPath(); c.arc(m, m, 98, (i / 16) * TAU, (i / 16 + 0.034) * TAU); c.stroke(); }
      } else if (kind === 'dot') {
        glow(60, 12); c.beginPath(); c.arc(m, m, 44, 0, TAU); c.fill();
        c.lineWidth = 10; c.beginPath(); c.arc(m, m, 92, 0, TAU); c.stroke();
      } else if (kind === 'soft') {
        const g = c.createRadialGradient(m, m, 0, m, m, m);
        g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.45, 'rgba(255,255,255,.55)'); g.addColorStop(1, 'rgba(255,255,255,0)');
        c.fillStyle = g; c.fillRect(0, 0, N, N);
      }
      return cv;
    });
  }

  // round droplet sprite (alpha + highlight) for particles
  function makeDropSprite() {
    return cached('drop', () => {
      const N = 64, cv = canvas(N, N), c = cv.getContext('2d');
      // R = brightness, A = coverage: a glassy bead with a dark rim and a hot specular dot
      const g = c.createRadialGradient(N * 0.5, N * 0.5, 0, N * 0.5, N * 0.5, N * 0.5);
      g.addColorStop(0, 'rgba(210,210,210,.55)'); g.addColorStop(0.55, 'rgba(150,150,150,.6)');
      g.addColorStop(0.85, 'rgba(70,70,70,.75)'); g.addColorStop(1, 'rgba(60,60,60,0)');
      c.fillStyle = g; c.fillRect(0, 0, N, N);
      const h = c.createRadialGradient(N * 0.38, N * 0.36, 0, N * 0.38, N * 0.36, N * 0.16);
      h.addColorStop(0, 'rgba(255,255,255,1)'); h.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = h; c.fillRect(0, 0, N, N);
      return cv;
    });
  }

  /* ─────────────────────────── renderer pool ─────────────────────────── */
  let pool = null;
  let supportedCache = null;
  function supported() {
    if (supportedCache !== null) return supportedCache;
    if (!THREE) return (supportedCache = false);
    try {
      const c = canvas(2, 2), gl = c.getContext('webgl2');
      supportedCache = !!gl;
      const lose = gl && gl.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
    } catch (e) { supportedCache = false; }
    return supportedCache;
  }
  function acquireRenderer() {
    if (pool && !pool.busy) { pool.busy = true; return pool; }
    const cv = canvas(16, 16);
    const gl = cv.getContext('webgl2', { antialias: true, alpha: false, depth: true, stencil: false, powerPreference: 'high-performance', preserveDrawingBuffer: false });
    if (!gl) return null;
    const renderer = new THREE.WebGLRenderer({ canvas: cv, context: gl, antialias: true });
    renderer.outputEncoding = THREE.sRGBEncoding;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.shadowMap.enabled = true;
    // wide PCF kernels (shadow.radius); two shadowed lamp cells overlap into a soft penumbra
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.setPixelRatio(1);
    const entry = { renderer, canvas: cv, busy: true, env: null, halfFloatRT: null };
    entry.halfFloatRT = !!(renderer.extensions.has('EXT_color_buffer_float') || renderer.extensions.has('EXT_color_buffer_half_float'));
    if (!pool) pool = entry;
    return entry;
  }
  function releaseRenderer(entry) {
    if (!entry) return;
    if (entry === pool) { entry.busy = false; if (entry.canvas.parentNode) entry.canvas.parentNode.removeChild(entry.canvas); return; }
    if (entry.env) entry.env.dispose();
    entry.renderer.dispose();
    entry.renderer.forceContextLoss();
    if (entry.canvas.parentNode) entry.canvas.parentNode.removeChild(entry.canvas);
  }
  function releaseAll() {
    if (!pool) return;
    if (pool.busy) return;   // a scene still uses it; it is released when that scene is disposed
    if (pool.env) pool.env.dispose();
    pool.renderer.dispose();
    pool.renderer.forceContextLoss();
    pool = null;
  }

  // Operating-room environment for reflections: dark room, round lamp head, soft wall panels.
  function buildEnv(entry) {
    if (entry.env) return entry.env;
    const pm = new THREE.PMREMGenerator(entry.renderer);
    const sc = new THREE.Scene();
    const disp = [];
    const mk = (geo, color, scalar) => {
      const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(scalar), side: THREE.DoubleSide });
      const me = new THREE.Mesh(geo, m); disp.push(geo, m); sc.add(me); return me;
    };
    // theatre walls (soft teal-grey), dark floor, a big round surgical lamp overhead plus
    // softboxes so steel and wet surfaces always have something bright to reflect
    const room = mk(new THREE.BoxGeometry(8, 5, 8), 0x6f7b80, 0.22); room.material.side = THREE.BackSide; room.position.y = 1.2;
    const floor = mk(new THREE.PlaneGeometry(8, 8), 0x23292b, 0.6); floor.rotation.x = -Math.PI / 2; floor.position.y = -1.15;
    const ceil = mk(new THREE.PlaneGeometry(8, 8), 0xdfe6e8, 0.55); ceil.rotation.x = Math.PI / 2; ceil.position.y = 3.6;
    const lamp = mk(new THREE.CircleGeometry(0.6, 48), 0xfff4e6, 14); lamp.position.set(0.35, 2.7, -0.7); lamp.rotation.x = Math.PI / 2;
    const ring = mk(new THREE.RingGeometry(0.6, 0.86, 48), 0x9aa3a6, 0.9); ring.position.set(0.35, 2.69, -0.7); ring.rotation.x = Math.PI / 2;
    for (let i = 0; i < 6; i++) {   // lamp cells
      const a = (i / 6) * Math.PI * 2;
      const c = mk(new THREE.CircleGeometry(0.11, 24), 0xffffff, 20); c.position.set(0.35 + Math.cos(a) * 0.36, 2.68, -0.7 + Math.sin(a) * 0.36); c.rotation.x = Math.PI / 2;
    }
    const lamp2 = mk(new THREE.CircleGeometry(0.38, 32), 0xf2f6ff, 7); lamp2.position.set(-1.5, 2.4, 0.9); lamp2.rotation.x = Math.PI / 2;
    const p1 = mk(new THREE.PlaneGeometry(2.6, 1.4), 0xeef4f7, 4.5); p1.position.set(3.9, 1.4, -0.4); p1.rotation.y = -Math.PI / 2;
    const p2 = mk(new THREE.PlaneGeometry(2.4, 1.2), 0xd6e2e6, 1.8); p2.position.set(-3.9, 1.2, 1); p2.rotation.y = Math.PI / 2;
    const p3 = mk(new THREE.PlaneGeometry(3.4, 1.2), 0x7cc4bd, 0.9); p3.position.set(0, 1.1, -3.9);
    const p4 = mk(new THREE.PlaneGeometry(3.0, 1.0), 0xf4f1ea, 1.4); p4.position.set(0.2, 1.0, 3.9); p4.rotation.y = Math.PI;
    const rt = pm.fromScene(sc, 0.035);
    disp.forEach(d => d.dispose());
    pm.dispose();
    entry.env = rt.texture;
    return entry.env;
  }

  /* ─────────────────────────── region presets ───────────────────────────
     axis: base surface curvature ('x' = cylinder along screen-right, limbs; 'z' = cylinder along
     screen-down, torso), R radius (m), size [W, H] (m), hair default (male), hairAngle (rad). */
  const REGION = {
    head:        { axis: 'z', R: 0.09,  size: [0.24, 0.22], hair: 0.04, hairAngle: 1.57 },
    face:        { axis: 'z', R: 0.075, size: [0.2, 0.18],  hair: 0.2,  hairAngle: -1.57 },
    neck:        { axis: 'x', R: 0.06,  size: [0.24, 0.16], hair: 0.15, hairAngle: 1.2 },
    chest:       { axis: 'z', R: 0.26,  size: [0.5, 0.36],  hair: 0.3,  hairAngle: 1.2 },
    back:        { axis: 'z', R: 0.32,  size: [0.5, 0.36],  hair: 0.12, hairAngle: 1.4 },
    abdomen:     { axis: 'z', R: 0.22,  size: [0.46, 0.34], hair: 0.26, hairAngle: 1.57 },
    pelvis:      { axis: 'z', R: 0.2,   size: [0.42, 0.3],  hair: 0.25, hairAngle: -1.4 },
    upper_arm:   { axis: 'x', R: 0.05,  size: [0.42, 0.155], hair: 0.26, hairAngle: 0.15 },
    lower_arm:   { axis: 'x', R: 0.04,  size: [0.42, 0.125], hair: 0.55, hairAngle: 0.12 },
    upper_leg:   { axis: 'x', R: 0.075, size: [0.46, 0.22], hair: 0.45, hairAngle: 0.1 },
    lower_leg:   { axis: 'x', R: 0.055, size: [0.44, 0.165], hair: 0.6,  hairAngle: 0.08 },
  };
  function regionPreset(region) {
    const r = String(region || 'chest').replace(/^[lr]_/, '');
    return REGION[r] || REGION.chest;
  }

  const QUALITY = {
    high:   { grid: 300, layer: 1024, field: 1024, macro: 1024, shadow: 2048, blur: 3.2, cells: 2, particles: 1400 },
    medium: { grid: 220, layer: 768,  field: 768,  macro: 1024, shadow: 1536, blur: 2.6, cells: 2, particles: 900 },
    low:    { grid: 150, layer: 512,  field: 512,  macro: 768,  shadow: 1024, blur: 2.0, cells: 1, particles: 500 },
  };

  /* ═══════════════════════════════════════════════════════════════════════════
     createScene
     ═══════════════════════════════════════════════════════════════════════════ */
  function createScene(container, opts = {}) {
    if (!THREE) throw new Error('NZA3D: three.js is not loaded');
    const o = Object.assign({
      tone: 0.25, region: 'chest', sex: 'm', seed: 1, hair: null, size: null, focus: null, drape: false,
      quality: 'high', exposure: 0.6, vignette: 0.72, work: null, keys: true, fullscreen: true, gravity: [0, 1], background: 0x050607,
    }, opts);
    const entry = acquireRenderer();
    if (!entry) throw new Error('NZA3D: WebGL2 is not available');
    const renderer = entry.renderer;
    const Q = QUALITY[o.quality] || QUALITY.high;
    const preset = regionPreset(o.region);
    const W = (o.size && o.size[0]) || preset.size[0];
    const H = (o.size && o.size[1]) || preset.size[1];
    const AXIS = o.flat ? 'none' : preset.axis;
    const RAD = preset.R;
    const female = o.sex === 'f';
    const hairAmt = o.hair !== null && o.hair !== undefined ? o.hair : preset.hair * (female ? 0.12 : 1);

    const bin = new Set();                  // everything that needs .dispose()
    const keep = x => { if (x) bin.add(x); return x; };
    const handlers = {};
    const S = {
      renderer, canvas: entry.canvas, patch: { W, H }, quality: o.quality, region: o.region,
      shape: { axis: AXIS, R: RAD }, pointer: { x: 0.5, y: 0.5 }, buttons: 0, MM, opts: o, time: 0,
    };
    S.on = (n, fn) => { (handlers[n] = handlers[n] || []).push(fn); return fn; };
    S.off = (n, fn) => { if (handlers[n]) handlers[n] = handlers[n].filter(f => f !== fn); };
    const emit = (n, ...a) => { const l = handlers[n]; if (l) for (let i = 0; i < l.length; i++) { try { l[i](...a); } catch (e) { console.error('[NZA3D]', n, e); } } };

    renderer.toneMappingExposure = o.exposure;
    renderer.setClearColor(o.background, 1);
    const cv = entry.canvas;
    cv.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;display:block;outline:none;touch-action:none';
    cv.tabIndex = -1;
    container.appendChild(cv);
    let vig = null;
    if (o.vignette > 0) {
      vig = document.createElement('div');
      vig.style.cssText = `position:absolute;inset:0;pointer-events:none;background:radial-gradient(120% 95% at 50% 46%,rgba(0,0,0,0) 38%,rgba(0,0,0,${(o.vignette * 0.55).toFixed(2)}) 78%,rgba(0,0,0,${o.vignette.toFixed(2)}) 100%)`;
      container.appendChild(vig);
    }

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(o.background);
    scene.environment = buildEnv(entry);
    const camera = new THREE.PerspectiveCamera(32, 16 / 9, 0.004, 4);
    S.scene = scene; S.camera = camera;

    /* ─────────── base surface ─────────── */
    const _p = new THREE.Vector3(), _n = new THREE.Vector3();
    function surf(s, t, P, N) {
      if (AXIS === 'x') {
        const a = t / RAD, c = Math.cos(a), si = Math.sin(a);
        P.set(s, RAD * c - RAD, RAD * si); N.set(0, c, si);
      } else if (AXIS === 'z') {
        const a = s / RAD, c = Math.cos(a), si = Math.sin(a);
        P.set(RAD * si, RAD * c - RAD, t); N.set(si, c, 0);
      } else { P.set(s, 0, t); N.set(0, 1, 0); }
    }
    // world point → { s, t, h } (h = height above the base surface)
    function toSurf(P) {
      if (AXIS === 'x') { const dy = P.y + RAD; return { s: P.x, t: Math.atan2(P.z, dy) * RAD, h: Math.hypot(dy, P.z) - RAD }; }
      if (AXIS === 'z') { const dy = P.y + RAD; return { s: Math.atan2(P.x, dy) * RAD, t: P.z, h: Math.hypot(dy, P.x) - RAD }; }
      return { s: P.x, t: P.z, h: P.y };
    }
    function tangents(s, t, Ts, Tt) {
      if (AXIS === 'x') { const a = t / RAD; Ts.set(1, 0, 0); Tt.set(0, -Math.sin(a), Math.cos(a)); }
      else if (AXIS === 'z') { const a = s / RAD; Ts.set(Math.cos(a), -Math.sin(a), 0); Tt.set(0, 0, 1); }
      else { Ts.set(1, 0, 0); Tt.set(0, 0, 1); }
    }
    const uvToST = uv => { const q = uvOf(uv); return [(q[0] - 0.5) * W, (0.5 - q[1]) * H]; };
    const stToUv = (s, t) => [s / W + 0.5, 0.5 - t / H];
    S.uvToST = uvToST; S.stToUv = stToUv; S._surf = surf; S._toSurf = toSurf; S._tangents = tangents;
    S.distanceUv = (a, b) => { const p = uvToST(a), q = uvToST(b); return Math.hypot(p[0] - q[0], p[1] - q[1]); };

    /* ─────────── lights ─────────── */
    // The operating lamp is a big multi-cell head: two shadowed cells a few cm apart (soft, double
    // penumbra) plus a shadowless centre cell that lifts the umbra, and a cool fill = room bounce.
    // `key` stays the main light (its direction drives the skin's subsurface wrap term).
    const mkCell = (color, intensity, shadow) => {
      const l = new THREE.SpotLight(color, intensity, 0, 0.38, 1.0, 0);
      if (shadow) {
        l.castShadow = true;
        l.shadow.mapSize.set(Q.shadow, Q.shadow);
        l.shadow.bias = -0.00015; l.shadow.normalBias = 0.0005;
        l.shadow.radius = Q.blur;
        l.shadow.camera.near = 0.3; l.shadow.camera.far = 2.4;
      }
      return l;
    };
    const twoCells = (Q.cells || 1) > 1;
    const key = mkCell(0xfff1e0, twoCells ? 0.82 : 1.0, true);
    const keyB = mkCell(0xfff3e6, twoCells ? 0.3 : 0.0, twoCells);
    const key2 = mkCell(0xfff6ec, twoCells ? 0.24 : 0.36, false);
    const fill = new THREE.SpotLight(0xe6f0ff, 0.24, 0, 0.45, 1.0, 0);
    const hemi = new THREE.HemisphereLight(0xdbe6ec, 0x3a2620, 0.1);
    scene.add(key, key.target, key2, key2.target, fill, fill.target, hemi);
    if (twoCells) scene.add(keyB, keyB.target);
    S.lights = { key, keyB, key2, fill, hemi };
    const keyDir = new THREE.Vector3();

    /* ─────────── skin geometry (denser around the focus) ─────────── */
    function axisCoords(n, len, f0, f1, factor) {
      const M = 4096, cum = new Float64Array(M + 1), soft = len * 0.035;
      for (let i = 0; i < M; i++) {
        const x = -len / 2 + ((i + 0.5) / M) * len;
        let w = 1;
        if (factor > 1 && f1 > f0) w += (factor - 1) * smooth(f0 - soft, f0 + soft, x) * (1 - smooth(f1 - soft, f1 + soft, x));
        cum[i + 1] = cum[i] + w;
      }
      const out = new Float32Array(n + 1);
      let j = 0;
      for (let k = 0; k <= n; k++) {
        const target = (k / n) * cum[M];
        while (j < M - 1 && cum[j + 1] < target) j++;
        const f = (target - cum[j]) / Math.max(1e-9, cum[j + 1] - cum[j]);
        out[k] = -len / 2 + ((j + clamp(f, 0, 1)) / M) * len;
      }
      out[0] = -len / 2; out[n] = len / 2;
      return out;
    }
    const NS = Q.grid, NT = Math.max(40, Math.round(Q.grid * Math.min(1.2, H / W) * 1.1));
    let fs0 = 0, fs1 = 0, ft0 = 0, ft1 = 0, fsF = 1, ftF = 1;
    if (o.focus) {
      const c = uvToST(o.focus.uv || [0.5, 0.5]), sz = o.focus.size || [0.08, 0.03];
      fs0 = c[0] - sz[0] / 2 - 0.012; fs1 = c[0] + sz[0] / 2 + 0.012; fsF = 3.2;
      ft0 = c[1] - sz[1] / 2 - 0.01; ft1 = c[1] + sz[1] / 2 + 0.01; ftF = 5.5;
    }
    const sCoords = axisCoords(NS, W, fs0, fs1, fsF), tCoords = axisCoords(NT, H, ft0, ft1, ftF);
    const skinGeo = keep(new THREE.BufferGeometry());
    {
      const nv = (NS + 1) * (NT + 1);
      const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), uv = new Float32Array(nv * 2);
      let k = 0;
      for (let j = 0; j <= NT; j++) {
        for (let i = 0; i <= NS; i++) {
          const s = sCoords[i], t = tCoords[j];
          surf(s, t, _p, _n);
          pos[k * 3] = _p.x; pos[k * 3 + 1] = _p.y; pos[k * 3 + 2] = _p.z;
          nor[k * 3] = _n.x; nor[k * 3 + 1] = _n.y; nor[k * 3 + 2] = _n.z;
          uv[k * 2] = s / W + 0.5; uv[k * 2 + 1] = 0.5 - t / H;
          k++;
        }
      }
      const idx = new Uint32Array(NS * NT * 6);
      let q = 0;
      for (let j = 0; j < NT; j++) for (let i = 0; i < NS; i++) {
        const a = j * (NS + 1) + i, b = a + 1, c = a + NS + 1, d = c + 1;
        idx[q++] = a; idx[q++] = c; idx[q++] = b; idx[q++] = b; idx[q++] = c; idx[q++] = d;
      }
      skinGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      skinGeo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
      skinGeo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      skinGeo.setIndex(new THREE.BufferAttribute(idx, 1));
      skinGeo.computeBoundingSphere();
      skinGeo.boundingSphere.radius += 0.05;
    }

    /* ─────────── shared noise texture ─────────── */
    const noiseTex = keep((() => {
      const d = buildNoise(), b = new Uint8Array(d.length);
      for (let i = 0; i < d.length; i++) b[i] = d[i] * 255;
      const t = new THREE.DataTexture(b, NOISE_N, NOISE_N, THREE.RGBAFormat, THREE.UnsignedByteType);
      t.wrapS = t.wrapT = THREE.RepeatWrapping; t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter;
      t.generateMipmaps = true; t.needsUpdate = true;
      return t;
    })());
    S._noiseTex = noiseTex;

    /* ─────────── skin textures ─────────── */
    const seed = (o.seed >>> 0) || 1;
    const MW = Q.macro, MHt = Math.max(64, Math.round(Q.macro * H / W));
    const macroCv = makeSkinMacro({ w: MW, h: MHt, W, H, tone: o.tone, seed, freckles: female ? 0.35 : 0.25, veins: AXIS === 'x' ? 0.9 : 0.45, veinAngle: preset.hairAngle });
    const macroTex = keep(new THREE.CanvasTexture(macroCv));
    macroTex.encoding = THREE.sRGBEncoding; macroTex.anisotropy = 4;
    const micro = makeSkinMicro({ seed: 7, tile: 0.036, hairAngle: preset.hairAngle, hairCount: 34, hairLen: female ? 0.0024 : 0.0042 });
    const microN = keep(new THREE.CanvasTexture(micro.normal));
    const microD = keep(new THREE.CanvasTexture(micro.detail));
    for (const t of [microN, microD]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; }
    const toneC = toneRGB(o.tone);
    const hairColor = new THREE.Color(o.tone < 0.12 ? 0x4a3020 : 0x1a100a).convertSRGBToLinear();

    /* ─────────── work window: the wound field and the paint layers cover this part of the patch
       (full resolution where the work happens instead of spreading it over the whole patch) ─────────── */
    const WR = (() => {
      const f = o.focus || { uv: [0.5, 0.5], size: [W * 0.3, H * 0.3] };
      const c = uvOf(f.uv || [0.5, 0.5]), sz = f.size || [0.08, 0.03];
      const ww = clamp(o.work ? o.work[0] : Math.max(sz[0] * 2.2 + 0.03, 0.15), 0.04, W);
      const hh = clamp(o.work ? o.work[1] : Math.max(sz[1] * 2.4 + 0.05, ww * 0.6), 0.03, H);
      const du = ww / W, dv = hh / H;
      return { u0: clamp(c[0] - du / 2, 0, 1 - du), v0: clamp(c[1] - dv / 2, 0, 1 - dv), du, dv, W: ww, H: hh };
    })();
    const toW = q => [(q[0] - WR.u0) / WR.du, (q[1] - WR.v0) / WR.dv];
    S.work = { uv: [WR.u0 + WR.du / 2, WR.v0 + WR.dv / 2], size: [WR.W, WR.H], rect: [WR.u0, WR.v0, WR.u0 + WR.du, WR.v0 + WR.dv] };

    /* ─────────── render targets: wound field + paint layers ─────────── */
    const FW = Q.field, FH = Math.max(32, Math.round(Q.field * WR.H / WR.W));
    const fieldRT = keep(new THREE.WebGLRenderTarget(FW, FH, {
      type: entry.halfFloatRT ? THREE.HalfFloatType : THREE.UnsignedByteType, format: THREE.RGBAFormat,
      minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false, stencilBuffer: false, generateMipmaps: false,
    }));
    const FIELD_ENC = entry.halfFloatRT ? 0 : 1;   // 8-bit fallback stores (h + 16) / 32 mm
    const LW = Q.layer, LH = Math.max(32, Math.round(Q.layer * WR.H / WR.W));
    // mipmapped: the skin shader reads a blurred level inside wound grooves (see SKIN_MAP)
    const mkLayerRT = () => keep(new THREE.WebGLRenderTarget(LW, LH, {
      type: THREE.UnsignedByteType, format: THREE.RGBAFormat, minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter,
      depthBuffer: false, stencilBuffer: false, generateMipmaps: true,
    }));
    const rtA = mkLayerRT(), rtB = mkLayerRT();
    {
      const prev = renderer.getRenderTarget();
      renderer.setClearColor(0x000000, 0);
      for (const rt of [rtA, rtB, fieldRT]) { renderer.setRenderTarget(rt); renderer.clear(true, false, false); }
      renderer.setRenderTarget(prev);
      renderer.setClearColor(o.background, 1);
    }

    /* ─────────── skin material (MeshPhysicalMaterial + injected layers) ─────────── */
    const U = {
      tField: { value: fieldRT.texture }, tMaskA: { value: rtA.texture }, tMaskB: { value: rtB.texture },
      tNoise: { value: noiseTex }, tMicro2: { value: microD },
      uPatch: { value: new THREE.Vector2(W, H) }, uFieldTexel: { value: new THREE.Vector2(1 / FW, 1 / FH) },
      uWR: { value: new THREE.Vector4(WR.u0, WR.v0, WR.du, WR.dv) }, uWork: { value: new THREE.Vector2(WR.W, WR.H) },
      uFieldEnc: { value: FIELD_ENC },
      uMicroRep: { value: 1 / 0.036 }, uHair: { value: hairAmt }, uHairColor: { value: hairColor },
      uKeyDir: { value: new THREE.Vector3(0, 1, 0) }, uKeyColor: { value: new THREE.Color(1, 0.96, 0.9) },
      uMicroNormal: { value: 1.25 }, uSkinRough: { value: 0.38 }, uFieldNormal: { value: 1.15 }, uSSS: { value: 0.75 },
      uDark: { value: o.tone }, uLayerTexel: { value: new THREE.Vector2(1 / LW, 1 / LH) }, uSebum: { value: 0.36 },
      uInsideLod: { value: clamp(Math.log2(0.0017 / (WR.W / LW)), 0, 6) },
    };
    S.uniforms = U;
    const skinMat = keep(new THREE.MeshPhysicalMaterial({
      map: macroTex, normalMap: microN, roughness: 0.46, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.1,
      sheen: 0.05, sheenRoughness: 0.7, sheenColor: new THREE.Color(1.0, 0.82, 0.74), ior: 1.4, specularIntensity: 0.62,
    }));
    skinMat.envMapIntensity = 0.32;
    skinMat.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, U);
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nuniform sampler2D tField;\nuniform float uFieldEnc;\nuniform vec4 uWR;')
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vec2 nzaWv = (uv - uWR.xy) / uWR.zw;
          float nzaH = texture2D(tField, nzaWv).g;
          if (uFieldEnc > 0.5) nzaH = nzaH * 32.0 - 16.0;
          nzaH *= smoothstep(0.0, 0.015, nzaWv.x) * smoothstep(0.0, 0.015, 1.0 - nzaWv.x) * smoothstep(0.0, 0.015, nzaWv.y) * smoothstep(0.0, 0.015, 1.0 - nzaWv.y);
          transformed += objectNormal * (nzaH * 0.001);`);
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\n' + SKIN_PARS)
        .replace('#include <map_fragment>', SKIN_MAP)
        .replace('#include <roughnessmap_fragment>', SKIN_ROUGH)
        .replace('#include <normal_fragment_maps>', SKIN_NORMAL)
        .replace('#include <clearcoat_normal_fragment_begin>', '#ifdef USE_CLEARCOAT\n vec3 clearcoatNormal = nzaMacroN;\n#endif')
        .replace('#include <lights_physical_fragment>', '#include <lights_physical_fragment>\n#ifdef USE_CLEARCOAT\n material.clearcoat = clamp(uSebum * (1.0 - nzaInside) + nzaWet * 0.95, 0.0, 1.0);\n material.clearcoatRoughness = clamp(mix(0.34, mix(0.07, 0.16, nzaInside), nzaWet) + geometryRoughness, 0.0525, 1.0);\n#endif')
        .replace('#include <aomap_fragment>', SKIN_AO);
    };
    skinMat.customProgramCacheKey = () => 'nza3d-skin-2';
    const skin = new THREE.Mesh(skinGeo, skinMat);
    skin.receiveShadow = true;
    skin.frustumCulled = false;
    scene.add(skin);
    S.skin = { mesh: skin, material: skinMat, macro: macroTex, tone: o.tone, toneRGB: toneC };

    /* ─────────── underlay (table cloth under limbs / around a curved patch) ─────────── */
    if (AXIS === 'x' || o.drape) {
      const weave = makeWeave({ threads: 22, seed: 4, fuzz: 0.4 });
      const wn = keep(new THREE.CanvasTexture(weave.normal)), wa = keep(new THREE.CanvasTexture(weave.albedo));
      for (const t of [wn, wa]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(70, 70); t.anisotropy = 8; }
      wa.encoding = THREE.sRGBEncoding;
      const cloth = new THREE.Mesh(keep(new THREE.PlaneGeometry(2.2, 2.2, 90, 90)), keep(new THREE.MeshPhysicalMaterial({
        color: new THREE.Color(o.drape && o.drape.color !== undefined ? o.drape.color : 0x2f7d86), map: wa, normalMap: wn,
        normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.92, sheen: 0.6, sheenRoughness: 0.8, sheenColor: new THREE.Color(0x9fe0dc),
      })));
      cloth.rotation.x = -Math.PI / 2;
      const gp = cloth.geometry.attributes.position;
      const R2 = rng(seed + 99);
      const folds = Array.from({ length: 7 }, () => ({ a: R2() * Math.PI, f: 6 + R2() * 14, p: R2() * 6, amp: 0.002 + R2() * 0.006 }));
      for (let i = 0; i < gp.count; i++) {
        const x = gp.getX(i), y = gp.getY(i);
        let z = 0;
        for (const f of folds) z += Math.sin((x * Math.cos(f.a) + y * Math.sin(f.a)) * f.f + f.p) * f.amp;
        z += (noiseAt(0, x * 2.2 + 3, y * 2.2) - 0.5) * 0.012;
        gp.setZ(i, z);
      }
      cloth.geometry.computeVertexNormals();
      cloth.position.y = AXIS === 'x' ? -RAD * 1.55 : -0.004;
      cloth.receiveShadow = true;
      if (AXIS === 'x' || !o.drape) scene.add(cloth);
      else keep(cloth.geometry);
      S._cloth = cloth;
    }

    /* ─────────── wound field pass ─────────── */
    const DATA_W = 64, DATA_H = 12, MAXW = 8, MAXP = 48, MAXB = 256;
    const dataArr = new Float32Array(DATA_W * DATA_H * 4);
    const dataTex = keep(new THREE.DataTexture(dataArr, DATA_W, DATA_H, THREE.RGBAFormat, THREE.FloatType));
    dataTex.magFilter = dataTex.minFilter = THREE.NearestFilter; dataTex.generateMipmaps = false; dataTex.needsUpdate = true;
    const fieldMat = keep(new THREE.ShaderMaterial({
      uniforms: { tData: { value: dataTex }, tNoise: { value: noiseTex }, uPatch: { value: new THREE.Vector2(W, H) }, uWR: { value: new THREE.Vector4(WR.u0, WR.v0, WR.du, WR.dv) }, uWounds: { value: 0 }, uBumps: { value: 0 }, uEnc: { value: FIELD_ENC } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
      fragmentShader: FIELD_FRAG, depthTest: false, depthWrite: false,
    }));
    const passScene = new THREE.Scene();
    const passQuad = new THREE.Mesh(keep(new THREE.PlaneGeometry(2, 2)), fieldMat);
    passQuad.frustumCulled = false;
    passScene.add(passQuad);
    const passCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    let fieldDirty = true;
    S._markField = () => { fieldDirty = true; };

    /* ─────────── paint layers ─────────── */
    const CH = { blood: [0, 0], grime: [0, 1], iodine: [0, 2], soot: [0, 3], bruise: [1, 0], wet: [1, 1], clot: [1, 2], eschar: [1, 3] };
    const MWm = 240, MHm = Math.max(16, Math.round(240 * WR.H / WR.W));      // CPU mirror over the work window (≈0.6 mm cells)
    const mirror = {};
    for (const k in CH) mirror[k] = new Float32Array(MWm * MHm);
    const MAXI = 1024;
    function mkBrush(sub) {
      const g = new THREE.InstancedBufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]), 3));
      g.setIndex([0, 1, 2, 0, 2, 3]);
      const attrs = {
        iCenter: new THREE.InstancedBufferAttribute(new Float32Array(MAXI * 2), 2),
        iRadius: new THREE.InstancedBufferAttribute(new Float32Array(MAXI * 2), 2),
        iMask: new THREE.InstancedBufferAttribute(new Float32Array(MAXI * 4), 4),
        iParams: new THREE.InstancedBufferAttribute(new Float32Array(MAXI * 4), 4),
        iExtra: new THREE.InstancedBufferAttribute(new Float32Array(MAXI * 2), 2),
      };
      for (const k in attrs) { attrs[k].setUsage(THREE.DynamicDrawUsage); g.setAttribute(k, attrs[k]); }
      g.instanceCount = 0;
      const m = new THREE.ShaderMaterial({
        uniforms: { tNoise: { value: noiseTex }, uPatch: { value: new THREE.Vector2(WR.W, WR.H) } },
        vertexShader: BRUSH_VERT, fragmentShader: BRUSH_FRAG, transparent: true, depthTest: false, depthWrite: false,
        blending: THREE.CustomBlending, blendEquation: sub ? THREE.ReverseSubtractEquation : THREE.AddEquation,
        blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor,
        blendEquationAlpha: sub ? THREE.ReverseSubtractEquation : THREE.AddEquation, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor,
      });
      keep(g); keep(m);
      const mesh = new THREE.Mesh(g, m);
      mesh.frustumCulled = false;
      return { g, attrs, mesh, n: 0 };
    }
    const brushes = [[mkBrush(false), mkBrush(true)], [mkBrush(false), mkBrush(true)]];   // [rt][add|sub]
    const brushScene = new THREE.Scene();
    const brushCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    const decays = {};

    function pushStamp(rtIdx, sub, cu, cv2, rx, ry, mask, amount, hard, grain, gscale, angle, sx, sy) {
      const b = brushes[rtIdx][sub ? 1 : 0];
      if (b.n >= MAXI) flushBrushes();
      const i = b.n++;
      b.attrs.iCenter.array[i * 2] = cu; b.attrs.iCenter.array[i * 2 + 1] = cv2;
      b.attrs.iRadius.array[i * 2] = rx; b.attrs.iRadius.array[i * 2 + 1] = ry;
      b.attrs.iMask.array.set(mask, i * 4);
      b.attrs.iParams.array[i * 4] = hard; b.attrs.iParams.array[i * 4 + 1] = grain; b.attrs.iParams.array[i * 4 + 2] = gscale; b.attrs.iParams.array[i * 4 + 3] = angle;
      b.attrs.iExtra.array[i * 2] = amount; b.attrs.iExtra.array[i * 2 + 1] = sx + sy * 0.37;
    }
    function flushBrushes() {
      const prevTarget = renderer.getRenderTarget(), prevAuto = renderer.autoClear;
      renderer.autoClear = false;
      for (let r = 0; r < 2; r++) {
        for (let k = 0; k < 2; k++) {
          const b = brushes[r][k];
          if (!b.n) continue;
          for (const a in b.attrs) b.attrs[a].needsUpdate = true;
          b.g.instanceCount = b.n;
          brushScene.add(b.mesh);
          renderer.setRenderTarget(r ? rtB : rtA);
          renderer.render(brushScene, brushCam);
          brushScene.remove(b.mesh);
          b.n = 0;
        }
      }
      renderer.setRenderTarget(prevTarget);
      renderer.autoClear = prevAuto;
    }
    function mirrorStamp(name, cu, cv2, rx, ry, angle, hard, amount, sub, rect) {
      const m = mirror[name];
      const cx = cu * MWm, cy = cv2 * MHm;
      const W = WR.W, H = WR.H;
      const ca = Math.cos(angle), sa = Math.sin(angle);
      const ext = Math.max(rx, ry);
      const x0 = rect ? 0 : Math.max(0, Math.floor(cx - (ext / W) * MWm) - 1), x1 = rect ? MWm - 1 : Math.min(MWm - 1, Math.ceil(cx + (ext / W) * MWm) + 1);
      const y0 = rect ? 0 : Math.max(0, Math.floor(cy - (ext / H) * MHm) - 1), y1 = rect ? MHm - 1 : Math.min(MHm - 1, Math.ceil(cy + (ext / H) * MHm) + 1);
      for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
          let f = 1;
          if (!rect) {
            const ds = ((x + 0.5) / MWm - cu) * W, dt = ((y + 0.5) / MHm - cv2) * H;
            const lx = (ds * ca + dt * sa) / rx, ly = (-ds * sa + dt * ca) / ry;
            const r = Math.sqrt(lx * lx + ly * ly);
            if (r >= 1) continue;
            f = 1 - smooth(hard, 1, r);
          }
          const i = y * MWm + x;
          m[i] = clamp(m[i] + (sub ? -1 : 1) * f * amount, 0, 1);
        }
      }
    }
    const layers = {
      names: Object.keys(CH),
      paint(name, uv, radius, amount, op = {}) {
        const ch = CH[name];
        if (!ch || !(amount > 0)) return;
        const q = toW(uvOf(uv));
        const rx = Array.isArray(radius) ? radius[0] : radius, ry = Array.isArray(radius) ? radius[1] : radius;
        if (q[0] < -rx / WR.W || q[1] < -ry / WR.H || q[0] > 1 + rx / WR.W || q[1] > 1 + ry / WR.H) return;
        const mask = [0, 0, 0, 0]; mask[ch[1]] = 1;
        const sub = op.mode === 'erase';
        const hard = op.hardness !== undefined ? op.hardness : 0.35;
        const grain = op.grain || 0, gs = op.grainScale || 40, ang = op.angle || 0;
        const a = clamp(amount, 0, 1);
        pushStamp(ch[0], sub, q[0], q[1], rx, ry, mask, a, hard, grain, gs, ang, op.seedX || Math.random() * 10, op.seedY || Math.random() * 10);
        mirrorStamp(name, q[0], q[1], rx, ry, ang, hard, a * (grain ? 1 - grain * 0.3 : 1), sub, false);
      },
      erase(name, uv, radius, amount, op = {}) { layers.paint(name, uv, radius, amount, Object.assign({}, op, { mode: 'erase' })); },
      stroke(name, a, b, radius, amount, op = {}) {
        const p = uvOf(a), q = uvOf(b);
        const d = S.distanceUv(p, q), r = Array.isArray(radius) ? Math.min(radius[0], radius[1]) : radius;
        const n = Math.max(1, Math.ceil(d / Math.max(r * 0.4, 0.0002)));
        for (let i = 0; i <= n; i++) {
          const f = i / n;
          layers.paint(name, [lerp(p[0], q[0], f), lerp(p[1], q[1], f)], radius, amount, op);
        }
      },
      splat(name, uv, radius, amount, op = {}) {
        const q = uvOf(uv), R = rng(op.seed !== undefined ? op.seed : Math.floor(Math.random() * 1e9));
        const n = op.count || 9;
        layers.paint(name, q, radius * 0.75, amount, Object.assign({ hardness: 0.25, grain: 0.55, grainScale: 70 }, op));
        for (let i = 0; i < n; i++) {
          const a = R() * TAU, d = R() * radius * 0.85, r = radius * (0.18 + R() * 0.45);
          const u = q[0] + (Math.cos(a) * d) / W, v = q[1] + (Math.sin(a) * d) / H;
          layers.paint(name, [u, v], [r * (0.7 + R() * 0.8), r], amount * (0.5 + R() * 0.6), Object.assign({ hardness: 0.2, grain: 0.6, grainScale: 60 + R() * 60, angle: R() * TAU }, op));
        }
      },
      fill(name, value) {
        const ch = CH[name];
        if (!ch) return;
        const mask = [0, 0, 0, 0]; mask[ch[1]] = 1;
        pushStamp(ch[0], true, 0.5, 0.5, WR.W, WR.H, mask, 1, 2, 0, 1, 0, 0, 0);
        if (value > 0) pushStamp(ch[0], false, 0.5, 0.5, WR.W, WR.H, mask, clamp(value, 0, 1), 2, 0, 1, 0, 0, 0);
        mirror[name].fill(clamp(value || 0, 0, 1));
      },
      clear(name) { layers.fill(name, 0); },
      decay(name, perSecond) { if (CH[name]) { if (perSecond > 0) decays[name] = { rate: perSecond, acc: 0 }; else delete decays[name]; } },
      sample(name, uv) {
        const m = mirror[name]; if (!m) return 0;
        const q = toW(uvOf(uv));
        if (q[0] < 0 || q[1] < 0 || q[0] > 1 || q[1] > 1) return 0;
        const x = clamp(q[0] * MWm - 0.5, 0, MWm - 1.001), y = clamp(q[1] * MHm - 0.5, 0, MHm - 1.001);
        const x0 = Math.floor(x), y0 = Math.floor(y), tx = x - x0, ty = y - y0;
        const i = y0 * MWm + x0;
        return lerp(lerp(m[i], m[i + 1], tx), lerp(m[i + MWm], m[i + MWm + 1], tx), ty);
      },
      _cells(uv, radius, fn) {
        const q = toW(uvOf(uv)), cx = q[0] * MWm, cy = q[1] * MHm, W = WR.W, H = WR.H;
        const rx = (radius / W) * MWm, ry = (radius / H) * MHm;
        const x0 = Math.max(0, Math.floor(cx - rx)), x1 = Math.min(MWm - 1, Math.ceil(cx + rx));
        const y0 = Math.max(0, Math.floor(cy - ry)), y1 = Math.min(MHm - 1, Math.ceil(cy + ry));
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
          const ds = ((x + 0.5) / MWm - q[0]) * W, dt = ((y + 0.5) / MHm - q[1]) * H;
          if (ds * ds + dt * dt <= radius * radius) fn(y * MWm + x, ds, dt);
        }
      },
      average(name, uv, radius) { const m = mirror[name]; let s = 0, n = 0; layers._cells(uv, radius, i => { s += m[i]; n++; }); return n ? s / n : 0; },
      coverage(name, uv, radius, thr = 0.2) { const m = mirror[name]; let s = 0, n = 0; layers._cells(uv, radius, i => { if (m[i] > thr) s++; n++; }); return n ? s / n : 0; },
      total(name, uv, radius) {
        const m = mirror[name]; let s = 0;
        if (uv === undefined) { for (let i = 0; i < m.length; i++) s += m[i]; return s; }
        layers._cells(uv, radius, i => { s += m[i]; });
        return s;
      },
      // cells near a polyline (uv list) within radius: reusable for "is the wound area clean" queries
      mask(points, radius) {
        const set = new Set();
        for (const p of points) layers._cells(p, radius, i => set.add(i));
        const idx = Int32Array.from(set);
        return {
          count: idx.length,
          sum(name) { const m = mirror[name]; let s = 0; for (let k = 0; k < idx.length; k++) s += m[idx[k]]; return s; },
          coverage(name, thr = 0.2) { const m = mirror[name]; let s = 0; for (let k = 0; k < idx.length; k++) if (m[idx[k]] > thr) s++; return idx.length ? s / idx.length : 0; },
        };
      },
      _mirror: mirror, _rt: [rtA, rtB],
    };
    S.layers = layers;
    function applyDecays(dt) {
      for (const name in decays) {
        const d = decays[name];
        d.acc += d.rate * dt;
        if (d.acc < 2.5 / 255) continue;
        const ch = CH[name], mask = [0, 0, 0, 0]; mask[ch[1]] = 1;
        pushStamp(ch[0], true, 0.5, 0.5, WR.W, WR.H, mask, d.acc, 2, 0, 1, 0, 0, 0);
        const m = mirror[name];
        for (let i = 0; i < m.length; i++) m[i] = Math.max(0, m[i] - d.acc);
        d.acc = 0;
      }
    }

    /* ═════════════ WOUNDS ═════════════ */
    const TYPE = { laceration: 1, stab: 1, incision: 1, gunshot: 2, burn: 3 };
    const woundList = [];
    const bumpList = [];
    let woundSeq = 0;

    function linePoints(def, R) {
      if (Array.isArray(def.points) && def.points.length >= 2) return def.points.map(p => uvToST(p));
      const c = uvToST(def.uv || [0.5, 0.5]);
      const L = def.length || 0.05, ang = def.angle || 0, n = clamp(Math.round(L / 0.0022), 10, MAXP);
      const ca = Math.cos(ang), sa = -Math.sin(ang);       // angle measured on screen (t grows downward)
      const curve = def.curve !== undefined ? def.curve : (R() - 0.5) * L * 0.12;
      const wob = def.wobble !== undefined ? def.wobble : 0.5;
      const pts = [];
      const off = R() * 10;
      for (let i = 0; i < n; i++) {
        const f = i / (n - 1), x = (f - 0.5) * L;
        let y = curve * (1 - 4 * (f - 0.5) * (f - 0.5));
        y += (noiseAt(0, off + f * L * 9, off) - 0.5) * wob * 0.004 + (noiseAt(1, off + f * L * 30, off * 2) - 0.5) * wob * 0.0012;
        pts.push([c[0] + x * ca - y * sa, c[1] + x * sa + y * ca]);
      }
      return pts;
    }

    function addWound(def = {}) {
      if (woundList.length >= MAXW) { console.warn('[NZA3D] wound limit reached'); return null; }
      const type = def.type || 'laceration';
      const code = TYPE[type] || 1;
      const R = rng((def.seed !== undefined ? def.seed : seed + woundSeq * 31) >>> 0);
      const w = { id: ++woundSeq, type, code, seedN: R() * 10 };
      const P = {
        laceration: { gape: 0.0042, depth: 0.007, jagged: 0.55, rim: 0.55, rimWidth: 0.0024, swell: 0.00025, taper: 0.55 },
        stab:       { gape: 0.0024, depth: 0.014, jagged: 0.12, rim: 0.3,  rimWidth: 0.0016, swell: 0.0003,  taper: 0.32 },
        incision:   { gape: 0.0016, depth: 0.006, jagged: 0.0,  rim: 0.12, rimWidth: 0.0012, swell: 0.0001,  taper: 0.45 },
        gunshot:    { radius: 0.0042, ring: 0.0018, depth: 0.012, jagged: 0.35, rim: 0.85, rimWidth: 0.002, swell: 0.0004 },
        burn:       { radius: 0.03, degree: 2, irregular: 0.45, rim: 0.8, rimWidth: 0.006, swell: 0 },
      }[type] || {};
      w.p = Object.assign({ cut: 1, open: 1 }, P, def);
      if (code === 1) {
        w.pts = linePoints(def, R);
        w.closure = new Float32Array(w.pts.length);
        w.gapeMul = new Float32Array(w.pts.length).fill(1);
        w.cum = new Float32Array(w.pts.length);
        for (let i = 1; i < w.pts.length; i++) w.cum[i] = w.cum[i - 1] + Math.hypot(w.pts[i][0] - w.pts[i - 1][0], w.pts[i][1] - w.pts[i - 1][1]);
        w.length = w.cum[w.pts.length - 1];
      } else {
        const c = uvToST(def.uv || [0.5, 0.5]);
        w.center = c;
        w.length = 0;
      }
      if (code === 3) {
        // blisters for partial-thickness burns
        const rr = Array.isArray(w.p.radius) ? w.p.radius : [w.p.radius, w.p.radius * 0.72];
        w.radii = rr;
        w.blisters = [];
        const nb = def.blisters !== undefined ? def.blisters : (w.p.degree >= 2 ? Math.round(4 + R() * 6) : 0);
        for (let i = 0; i < nb; i++) {
          const a = R() * TAU, d = Math.sqrt(R()) * 0.85;
          const uvb = stToUv(w.center[0] + Math.cos(a) * d * rr[0], w.center[1] + Math.sin(a) * d * rr[1]);
          w.blisters.push(addBump({ uv: uvb, radius: 0.002 + R() * 0.006, height: 0.0007 + R() * 0.0018, kind: 'blister' }));
        }
      }
      Object.assign(w, woundApi(w));
      woundList.push(w);
      fieldDirty = true;
      return w;
    }

    function woundApi(w) {
      const api = {
        set(patch) {
          Object.assign(w.p, patch || {});
          if (patch && patch.uv && w.center) w.center = uvToST(patch.uv);
          fieldDirty = true;
          return api;
        },
        remove() {
          const i = woundList.indexOf(w);
          if (i >= 0) woundList.splice(i, 1);
          if (w.blisters) w.blisters.forEach(b => b.remove());
          fieldDirty = true;
        },
        // point on the centre line at fraction tN of the length
        at(tN) {
          if (w.code !== 1) return { uv: stToUv(w.center[0], w.center[1]), s: w.center[0], t: w.center[1], dir: [1, 0], nrm: [0, 1] };
          const L = clamp(tN, 0, 1) * w.length;
          let i = 1;
          while (i < w.pts.length - 1 && w.cum[i] < L) i++;
          const a = w.pts[i - 1], b = w.pts[i], seg = w.cum[i] - w.cum[i - 1] || 1e-9;
          const f = clamp((L - w.cum[i - 1]) / seg, 0, 1);
          const s = lerp(a[0], b[0], f), t = lerp(a[1], b[1], f);
          const dl = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
          const dir = [(b[0] - a[0]) / dl, (b[1] - a[1]) / dl];
          return { uv: stToUv(s, t), s, t, dir, nrm: [-dir[1], dir[0]], seg: i - 1, f };
        },
        closureAt(tN) {
          if (w.code !== 1) return 0;
          const r = api.at(tN);
          return lerp(w.closure[r.seg], w.closure[r.seg + 1], r.f);
        },
        envelope(tN) {
          const cut = Math.max(w.p.cut, 1e-4);
          if (tN > cut) return 0;
          return Math.pow(Math.max(Math.sin(Math.PI * clamp(tN / cut, 0, 1)), 0), w.p.taper);
        },
        halfGape(tN) {
          if (w.code === 2) return w.p.radius * w.p.open;
          if (w.code !== 1) return 0;
          const r = api.at(tN);
          const gm = lerp(w.gapeMul[r.seg], w.gapeMul[r.seg + 1], r.f);
          return 0.5 * w.p.gape * w.p.open * api.envelope(tN) * (1 - api.closureAt(tN)) * gm;
        },
        // point beside the wound: side +1 = left of the direction of travel (screen up for a left→right cut)
        edge(tN, side, offset = 0) {
          const r = api.at(tN), hg = api.halfGape(tN), d = (hg + offset) * (side >= 0 ? 1 : -1);
          return stToUv(r.s + r.nrm[0] * d, r.t + r.nrm[1] * d);
        },
        // nearest point of the centre line: distance (m), fraction, side (+1 / -1, as in edge()), arc length
        locate(uv) {
          const p = uvToST(uv);
          if (w.code !== 1) { const d = Math.hypot(p[0] - w.center[0], p[1] - w.center[1]); return { d, tN: 0, side: 1, L: 0 }; }
          let best = Infinity, bl = 0, side = 1;
          for (let i = 1; i < w.pts.length; i++) {
            const a = w.pts[i - 1], b = w.pts[i];
            const ab = [b[0] - a[0], b[1] - a[1]], l2 = ab[0] * ab[0] + ab[1] * ab[1] || 1e-12;
            const tt = clamp(((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2, 0, 1);
            const qx = a[0] + ab[0] * tt, qy = a[1] + ab[1] * tt;
            const d = Math.hypot(p[0] - qx, p[1] - qy);
            if (d < best) {
              best = d; bl = w.cum[i - 1] + tt * Math.sqrt(l2);
              side = (ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) >= 0 ? 1 : -1;   // same convention as edge()
            }
          }
          return { d: best, tN: bl / (w.length || 1), side, L: bl };
        },
        // raise closure around tN (stitch): gaussian in arc length
        close(tN, amount = 1, sigmaN = 0.07) {
          if (w.code !== 1) return;
          for (let i = 0; i < w.pts.length; i++) {
            const f = w.cum[i] / (w.length || 1);
            const g = Math.exp(-((f - tN) * (f - tN)) / (2 * sigmaN * sigmaN));
            w.closure[i] = Math.max(w.closure[i], clamp(amount * g, 0, 1));
          }
          fieldDirty = true;
        },
        setClosure(fn) { if (w.code !== 1) return; for (let i = 0; i < w.pts.length; i++) w.closure[i] = clamp(fn(w.cum[i] / (w.length || 1)), 0, 1); fieldDirty = true; },
        points() { return w.code === 1 ? w.pts.map(p => stToUv(p[0], p[1])) : [stToUv(w.center[0], w.center[1])]; },
      };
      return api;
    }

    function addBump(def) {
      if (bumpList.length >= MAXB) bumpList.shift();
      const b = { st: uvToST(def.uv || [0.5, 0.5]), radius: def.radius || 0.003, height: def.height || 0.0008, kind: def.kind || 'bump' };
      b.set = p => {
        if (p.uv) b.st = uvToST(p.uv);
        if (p.radius !== undefined) b.radius = p.radius;
        if (p.height !== undefined) b.height = p.height;
        fieldDirty = true; return b;
      };
      b.remove = () => { const i = bumpList.indexOf(b); if (i >= 0) bumpList.splice(i, 1); fieldDirty = true; };
      b.uv = () => stToUv(b.st[0], b.st[1]);
      bumpList.push(b);
      fieldDirty = true;
      return b;
    }

    function writeField() {
      dataArr.fill(0);
      const put = (x, y, a, b, c, d) => { const i = (y * DATA_W + x) * 4; dataArr[i] = a; dataArr[i + 1] = b; dataArr[i + 2] = c; dataArr[i + 3] = d; };
      woundList.forEach((w, row) => {
        const p = w.p, mm = 1000;
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        const grow = (s, t, r) => { x0 = Math.min(x0, s - r); y0 = Math.min(y0, t - r); x1 = Math.max(x1, s + r); y1 = Math.max(y1, t + r); };
        if (w.code === 1) {
          put(0, row, 1, w.pts.length, p.gape * mm, p.depth * mm);
          const pad = (p.gape * 1.2 + p.rimWidth * 4 + 0.004);
          w.pts.forEach((q, i) => {
            grow(q[0], q[1], pad);
            put(8 + i, row, q[0] * mm, q[1] * mm, w.closure[i], w.gapeMul[i]);
          });
          put(4, row, w.length * mm, 0, 0, 0);
        } else if (w.code === 2) {
          put(0, row, 2, 0, 0, p.depth * mm);
          grow(w.center[0], w.center[1], p.radius * 2.2 + p.ring * 3 + 0.004);
          put(4, row, w.center[0] * mm, w.center[1] * mm, p.radius * mm, p.ring * mm);
        } else {
          put(0, row, 3, 0, 0, 0);
          const rr = w.radii || [p.radius, p.radius];
          grow(w.center[0], w.center[1], Math.max(rr[0], rr[1]) * 1.9 + 0.006);
          put(4, row, w.center[0] * mm, w.center[1] * mm, rr[0] * mm, rr[1] * mm);
          put(5, row, p.irregular, p.degree, 0, 0);
        }
        put(1, row, p.cut, p.open, p.rimWidth * mm, p.rim);
        put(2, row, p.jagged || 0, w.seedN, p.taper || 0.5, p.swell * mm);
        put(3, row, x0 * mm, y0 * mm, x1 * mm, y1 * mm);
      });
      bumpList.forEach((b, i) => put(i % 64, 8 + Math.floor(i / 64), b.st[0] * 1000, b.st[1] * 1000, b.radius * 1000, b.height * 1000));
      dataTex.needsUpdate = true;
      fieldMat.uniforms.uWounds.value = woundList.length;
      fieldMat.uniforms.uBumps.value = bumpList.length;
    }
    function renderField() {
      writeField();
      const prev = renderer.getRenderTarget();
      renderer.setRenderTarget(fieldRT);
      renderer.render(passScene, passCam);
      renderer.setRenderTarget(prev);
      fieldDirty = false;
    }

    // CPU height (m) at patch coords — mirrors FIELD_FRAG (without the noisy edge jitter)
    function heightAt(s, t) {
      let h = 0;
      const Pm = [s * 1000, t * 1000];
      for (const w of woundList) {
        const p = w.p;
        if (w.code === 1) {
          const api = w;
          const loc = api.locate(stToUv(s, t));
          const best = loc.d * 1000;
          if (best > (p.gape * 1000 + p.rimWidth * 4000 + 4)) continue;
          const env = api.envelope(loc.tN);
          const clos = api.closureAt(loc.tN);
          const g = p.gape * 1000 * p.open * env * (1 - clos);
          const halfG = 0.5 * g;
          const ins = halfG > 0.03 ? 1 - smooth(halfG - 0.07, halfG + 0.07, best) : 0;
          const x = clamp(best / Math.max(halfG, 0.03), 0, 1);
          const dep = p.depth * 1000 * Math.pow(env, 0.4) * (1 - 0.96 * clos) * lerp(0.35, 1, p.open);
          h += ins * -dep * (1 - Math.pow(x, 2.4));
          const ed = Math.max(best - halfG, 0);
          const near = Math.exp(-Math.pow(ed / Math.max(p.rimWidth * 1000, 0.05), 2));
          const exists = loc.tN <= p.cut + 1e-4 && p.cut > 0.0005 ? 1 : 0;
          h += (1 - ins) * (p.swell * 1000 * near * Math.sqrt(env + 1e-4) * exists - 0.12 * dep * Math.exp(-Math.pow(ed / 0.3, 2)));
          h += exists * clos * 0.28 * Math.exp(-Math.pow(best / 1.4, 2)) * Math.sqrt(env + 1e-4);
        } else if (w.code === 2) {
          const d = Math.hypot(Pm[0] - w.center[0] * 1000, Pm[1] - w.center[1] * 1000);
          const r = p.radius * 1000 * Math.max(p.open, 0.05);
          if (d > r * 3 + p.ring * 4000) continue;
          const ins = 1 - smooth(r - 0.08, r + 0.08, d), x = clamp(d / Math.max(r, 0.05), 0, 1);
          h += ins * (-p.depth * 1000 * Math.pow(1 - x, 1.8) - 0.5 * (1 - x * x));
          const ed = Math.max(d - r, 0);
          h += (1 - ins) * p.swell * 1000 * Math.exp(-Math.pow(ed / (p.ring * 1000 * 1.6 + 0.1), 2));
        } else {
          const rr = w.radii;
          const q = [(Pm[0] - w.center[0] * 1000) / (rr[0] * 1000), (Pm[1] - w.center[1] * 1000) / (rr[1] * 1000)];
          const dn = Math.hypot(q[0], q[1]);
          if (dn < 1) h += p.degree >= 2.5 ? -0.2 : 0.08;
        }
      }
      for (const b of bumpList) {
        const dx = Pm[0] - b.st[0] * 1000, dy = Pm[1] - b.st[1] * 1000, r = b.radius * 1000;
        const d2 = dx * dx + dy * dy;
        if (d2 < r * r) { const f = 1 - d2 / (r * r); h += b.height * 1000 * f * f; }
      }
      return h * MM;
    }
    S.heightAt = uv => { const q = uvToST(uv); return heightAt(q[0], q[1]); };
    S.wounds = {
      add: addWound,
      remove: w => w && w.remove(),
      clear: () => { while (woundList.length) woundList[0].remove(); },
      get list() { return woundList.slice(); },
    };
    S.bumps = { add: addBump, get list() { return bumpList.slice(); }, clear: () => { bumpList.length = 0; fieldDirty = true; } };

    /* ═════════════ PICKING ═════════════ */
    const ray = new THREE.Raycaster();
    const _v2 = new THREE.Vector2(), _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3();
    function pointerFrac(p) {
      if (!p) return S.pointer;
      if (p.clientX !== undefined) {
        const r = cv.getBoundingClientRect();
        const zx = r.width ? cv.width / r.width : 1;
        return { x: clamp((p.clientX - r.left) / (r.width || 1), 0, 1), y: clamp((p.clientY - r.top) / (r.height || 1), 0, 1), zx };
      }
      return p;
    }
    function surfaceAtST(s, t, out = {}) {
      const P = out.point || new THREE.Vector3(), N = out.normal || new THREE.Vector3();
      surf(s, t, P, N);
      const h = heightAt(s, t);
      P.addScaledVector(N, h);
      // normal from finite differences of the displaced surface
      const e = 0.0006, Ts = _a, Tt = _b;
      tangents(s, t, Ts, Tt);
      const hs = (heightAt(s + e, t) - heightAt(s - e, t)) / (2 * e), ht = (heightAt(s, t + e) - heightAt(s, t - e)) / (2 * e);
      N.addScaledVector(Ts, -hs).addScaledVector(Tt, -ht).normalize();
      out.point = P; out.normal = N; out.height = h; out.s = s; out.t = t; out.uv = stToUv(s, t);
      return out;
    }
    S.surfaceAt = uv => { const q = uvToST(uv); return surfaceAtST(q[0], q[1]); };
    S._surfaceAtST = surfaceAtST;

    function raycast(p) {
      const f = pointerFrac(p);
      _v2.set(f.x * 2 - 1, -(f.y * 2 - 1));
      ray.setFromCamera(_v2, camera);
      const O = ray.ray.origin, D = ray.ray.direction;
      // march from the camera until the ray goes below the displaced surface, then bisect
      const above = lam => { _c.copy(O).addScaledVector(D, lam); const q = toSurf(_c); return q.h - heightAt(q.s, q.t); };
      let lo = 0, hi = 0, prev = above(0), step = 0.004, lam = 0, found = false;
      const maxL = 3;
      while (lam < maxL) {
        lam += step;
        const v = above(lam);
        if (v <= 0) { lo = lam - step; hi = lam; found = true; break; }
        step = clamp(v * 0.6, 0.0006, 0.02);
        prev = v;
      }
      if (!found) return null;
      for (let i = 0; i < 18; i++) { const m = (lo + hi) / 2; if (above(m) > 0) lo = m; else hi = m; }
      _c.copy(O).addScaledVector(D, hi);
      const q = toSurf(_c);
      if (Math.abs(q.s) > W / 2 || Math.abs(q.t) > H / 2) return null;
      const out = surfaceAtST(q.s, q.t, {});
      out.distance = hi;
      return out;
    }
    S.raycast = raycast;
    const _pv = new THREE.Vector3();
    S.project = target => {
      if (target && target.isVector3) _pv.copy(target);
      else { const q = uvToST(target); surfaceAtST(q[0], q[1], { point: _pv, normal: new THREE.Vector3() }); }
      _pv.project(camera);
      return { x: (_pv.x + 1) / 2, y: (1 - _pv.y) / 2, visible: _pv.z < 1 && _pv.z > -1 };
    };

    /* ═════════════ CAMERA CONTROLS ═════════════ */
    const ctl = {
      enabled: true,
      limits: { yaw: 0.85, pitchMin: 0.62, pitchMax: 1.48, distMin: 0.06, distMax: 0.6, pan: 0.07 },
      home: { s: 0, t: 0, yaw: 0, pitch: 1.18, dist: 0.24 },
      goal: { s: 0, t: 0, yaw: 0, pitch: 1.18, dist: 0.24 },
      cur: { s: 0, t: 0, yaw: 0, pitch: 1.18, dist: 0.24 },
      shakeAmp: 0, shakeT: 0, shakeEnd: 0,
    };
    const camT = new THREE.Vector3(), camN = new THREE.Vector3(), camS = new THREE.Vector3(), camTt = new THREE.Vector3();
    const camM = new THREE.Matrix4();
    function applyCamera(dt) {
      const k = 1 - Math.exp(-dt * 9);
      for (const kk of ['s', 't', 'yaw', 'pitch', 'dist']) ctl.cur[kk] += (ctl.goal[kk] - ctl.cur[kk]) * k;
      const c = ctl.cur;
      surf(c.s, c.t, camT, camN);
      tangents(c.s, c.t, camS, camTt);
      const cp = Math.cos(c.pitch), sp = Math.sin(c.pitch);
      const dir = new THREE.Vector3().addScaledVector(camS, Math.sin(c.yaw) * cp).addScaledVector(camTt, Math.cos(c.yaw) * cp).addScaledVector(camN, sp);
      camera.position.copy(camT).addScaledVector(dir, c.dist);
      // shake
      if (ctl.shakeAmp > 0.0001) {
        ctl.shakeT += dt;
        const left = Math.max(0, ctl.shakeEnd - performance.now()) / 1000;
        const a = ctl.shakeAmp * Math.min(1, left * 3);
        const j = c.dist * 0.035 * a;
        camera.position.x += (noiseAt(0, ctl.shakeT * 9, 0.1) - 0.5) * j;
        camera.position.y += (noiseAt(1, ctl.shakeT * 9, 0.6) - 0.5) * j;
        camera.position.z += (noiseAt(0, 0.3, ctl.shakeT * 9) - 0.5) * j;
        if (left <= 0) ctl.shakeAmp = 0;
      }
      const fwd = _a.copy(camT).sub(camera.position).normalize();
      const right = _b.crossVectors(fwd, camN);
      if (right.lengthSq() < 1e-8) right.copy(camS);
      right.normalize();
      const up = _c.crossVectors(right, fwd).normalize();
      camM.makeBasis(right, up, fwd.clone().negate());
      camera.quaternion.setFromRotationMatrix(camM);
      camera.updateMatrixWorld();
    }
    const controls = {
      get enabled() { return ctl.enabled; }, set enabled(v) { ctl.enabled = !!v; },
      limits: ctl.limits,
      frame(uv, width, op = {}) {
        const q = uvToST(uv);
        const aspect = camera.aspect || 16 / 9;
        const hfov = 2 * Math.atan(Math.tan((camera.fov * Math.PI) / 360) * aspect);
        const d = clamp((width / 2) / Math.tan(hfov / 2), ctl.limits.distMin, ctl.limits.distMax);
        Object.assign(ctl.home, { s: q[0], t: q[1], yaw: op.yaw || 0, pitch: op.pitch || 1.18, dist: d });
        Object.assign(ctl.goal, ctl.home);
        if (op.instant !== false) Object.assign(ctl.cur, ctl.home);
        ctl.limits.distMax = Math.max(ctl.limits.distMax, d * 1.8);
        return controls;
      },
      recenter() { Object.assign(ctl.goal, ctl.home); },
      set(p) { Object.assign(ctl.goal, p); if (p.target) { const q = uvToST(p.target); ctl.goal.s = q[0]; ctl.goal.t = q[1]; } return controls; },
      shake(amount = 0.5, ms = 400) { ctl.shakeAmp = Math.max(ctl.shakeAmp, amount); ctl.shakeEnd = performance.now() + ms; },
      get state() { return Object.assign({}, ctl.cur); },
      get home() { return Object.assign({}, ctl.home); },
    };
    S.controls = controls;

    /* input */
    let drag = null;
    const onDown = e => {
      S.buttons = e.buttons;
      const f = pointerFrac(e); S.pointer.x = f.x; S.pointer.y = f.y;
      if (e.button === 2 && ctl.enabled) { drag = { x: e.clientX, y: e.clientY, pan: e.shiftKey }; e.preventDefault(); }
      emit('down', e, f);
    };
    const onMove = e => {
      S.buttons = e.buttons;
      const f = pointerFrac(e); S.pointer.x = f.x; S.pointer.y = f.y;
      if (drag && ctl.enabled) {
        const dx = (e.clientX - drag.x) / Math.max(1, cv.clientWidth), dy = (e.clientY - drag.y) / Math.max(1, cv.clientHeight);
        drag.x = e.clientX; drag.y = e.clientY;
        if (drag.pan || e.shiftKey) {
          const sc = ctl.cur.dist * 0.9;
          const L = ctl.limits.pan;
          ctl.goal.s = clamp(ctl.goal.s - dx * sc * Math.cos(ctl.cur.yaw) - dy * sc * Math.sin(ctl.cur.yaw) * 0, ctl.home.s - L, ctl.home.s + L);
          ctl.goal.t = clamp(ctl.goal.t - dy * sc, ctl.home.t - L, ctl.home.t + L);
        } else {
          ctl.goal.yaw = clamp(ctl.goal.yaw - dx * 2.4, -ctl.limits.yaw, ctl.limits.yaw);
          ctl.goal.pitch = clamp(ctl.goal.pitch + dy * 2.0, ctl.limits.pitchMin, ctl.limits.pitchMax);
        }
      }
      emit('pointer', e, f);
    };
    const onUp = e => {
      S.buttons = e.buttons;
      if (e.button === 2) drag = null;
      emit('up', e, pointerFrac(e));
    };
    const onWheel = e => {
      if (!ctl.enabled) return;
      e.preventDefault();
      ctl.goal.dist = clamp(ctl.goal.dist * Math.pow(1.12, Math.sign(e.deltaY)), ctl.limits.distMin, ctl.limits.distMax);
    };
    const onCtx = e => e.preventDefault();
    const onKey = e => {
      if (!o.keys || e.repeat) return;
      if ((e.key === 'r' || e.key === 'R') && !e.ctrlKey && !e.metaKey && cv.isConnected) controls.recenter();
    };
    cv.addEventListener('pointerdown', onDown);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    cv.addEventListener('wheel', onWheel, { passive: false });
    cv.addEventListener('contextmenu', onCtx);
    window.addEventListener('keydown', onKey);

    /* ═════════════ MATERIALS (tools, thread, markers) ═════════════ */
    const M = {
      steel: keep(new THREE.MeshStandardMaterial({ color: 0xdfe4e8, metalness: 1, roughness: 0.2 })),
      steelSatin: keep(new THREE.MeshStandardMaterial({ color: 0xc6cdd2, metalness: 1, roughness: 0.36 })),
      steelDark: keep(new THREE.MeshStandardMaterial({ color: 0x6e767c, metalness: 1, roughness: 0.42 })),
      gold: keep(new THREE.MeshStandardMaterial({ color: 0xe0b45a, metalness: 1, roughness: 0.26 })),
      clear: keep(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.05, transparent: true, opacity: 0.22, clearcoat: 1, clearcoatRoughness: 0.04, depthWrite: false, side: THREE.DoubleSide })),
      fluid: keep(new THREE.MeshPhysicalMaterial({ color: 0xdff2ff, roughness: 0.1, transparent: true, opacity: 0.18, depthWrite: false })),
      rubber: keep(new THREE.MeshStandardMaterial({ color: 0x24282b, roughness: 0.62 })),
      white: keep(new THREE.MeshPhysicalMaterial({ color: 0xf1f4f4, roughness: 0.4, clearcoat: 0.35, clearcoatRoughness: 0.3 })),
      bottle: keep(new THREE.MeshPhysicalMaterial({ color: 0xecf1f1, roughness: 0.34, clearcoat: 0.6, clearcoatRoughness: 0.2, transparent: true, opacity: 0.96 })),
      teal: keep(new THREE.MeshPhysicalMaterial({ color: 0x08afa2, roughness: 0.32, clearcoat: 0.6, clearcoatRoughness: 0.2 })),
      tealClear: keep(new THREE.MeshPhysicalMaterial({ color: 0x0fd4c4, roughness: 0.15, transparent: true, opacity: 0.75, clearcoat: 1 })),
      dark: keep(new THREE.MeshPhysicalMaterial({ color: 0x1b1f22, roughness: 0.45, clearcoat: 0.4 })),
      thread: keep(new THREE.MeshPhysicalMaterial({ color: 0x060914, roughness: 0.38, clearcoat: 0.55, clearcoatRoughness: 0.22 })),
    };
    const tex = (cvs, srgb = true) => { const t = keep(new THREE.CanvasTexture(cvs)); if (srgb) t.encoding = THREE.sRGBEncoding; t.anisotropy = 4; return t; };
    const geo = g => keep(g);
    const add = (parent, g, m, cast = true) => { const me = new THREE.Mesh(geo(g), m); me.castShadow = cast; parent.add(me); return me; };

    // loft a closed box section along +Y: rows [{ y, w, t, x?, z? }] (w across X, t across Z)
    function loft(rows) {
      const g = new THREE.BufferGeometry(), pos = [], idx = [];
      rows.forEach(r => {
        const x = r.x || 0, z = r.z || 0, hw = r.w / 2, ht = r.t / 2;
        pos.push(x - hw, r.y, z - ht, x + hw, r.y, z - ht, x + hw, r.y, z + ht, x - hw, r.y, z + ht);
      });
      for (let i = 0; i < rows.length - 1; i++) {
        for (let k = 0; k < 4; k++) {
          const a = i * 4 + k, b = i * 4 + ((k + 1) % 4), c = a + 4, d = b + 4;
          idx.push(a, b, d, a, d, c);
        }
      }
      const last = (rows.length - 1) * 4;
      idx.push(0, 2, 1, 0, 3, 2, last, last + 1, last + 2, last, last + 2, last + 3);
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      g.setIndex(idx);
      const ng = g.toNonIndexed(); g.dispose();
      ng.computeVertexNormals();
      return ng;
    }
    const lathe = (pts, seg = 40) => new THREE.LatheGeometry(pts.map(p => new THREE.Vector2(p[0], p[1])), seg);
    const tube = (pts, r, seg = 40, rad = 8) => new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts.map(p => (p.isVector3 ? p : new THREE.Vector3(p[0], p[1], p[2] || 0))), false, 'centripetal'), seg, r, rad, false);

    /* ═════════════ TOOLS ═════════════ */
    function buildSaline() {
      const g = new THREE.Group(), body = new THREE.Group();
      g.add(body);
      add(body, lathe([[0, 0], [0.0007, 0.0002], [0.0011, 0.004], [0.0032, 0.021], [0.0036, 0.023], [0, 0.023]], 28), M.white);
      const cap = add(body, lathe([[0, 0.022], [0.0105, 0.023], [0.011, 0.024], [0.011, 0.037], [0.0108, 0.0385], [0, 0.0385]], 36), M.teal);
      for (let i = 0; i < 24; i++) { const r = add(cap, new THREE.BoxGeometry(0.0012, 0.012, 0.0009), M.teal); const a = (i / 24) * TAU; r.position.set(Math.cos(a) * 0.011, 0.0305, Math.sin(a) * 0.011); r.rotation.y = -a; }
      const shell = add(body, lathe([[0.0115, 0.038], [0.0125, 0.042], [0.022, 0.054], [0.0305, 0.066], [0.0325, 0.078], [0.033, 0.17], [0.0322, 0.181], [0.028, 0.186], [0, 0.1865]], 48), M.bottle);
      const lab = add(body, new THREE.CylinderGeometry(0.03335, 0.03335, 0.064, 48, 1, true, -0.4, Math.PI * 1.5), keep(new THREE.MeshPhysicalMaterial({ map: tex(makeLabel('saline')), roughness: 0.42, clearcoat: 0.5 })));
      lab.position.y = 0.122;
      return {
        group: g, set(p) { if (p.squeeze !== undefined) { const s = 1 - p.squeeze * 0.07; shell.scale.set(s, 1, s); lab.scale.set(s, 1, s); } },
      };
    }
    function buildSyringe() {
      const g = new THREE.Group();
      add(g, new THREE.ConeGeometry(0.00026, 0.0014, 10).translate(0, 0.0007, 0), M.steel);
      add(g, new THREE.CylinderGeometry(0.00027, 0.00027, 0.024, 10).translate(0, 0.0134, 0), M.steel);
      add(g, lathe([[0.0007, 0.025], [0.0024, 0.0265], [0.0026, 0.031], [0.0036, 0.0335], [0.0036, 0.0348], [0, 0.0348]], 24), M.tealClear);
      add(g, lathe([[0.0009, 0.0345], [0.0013, 0.0372], [0.0059, 0.0392], [0.0061, 0.0395]], 32), M.clear, false);
      const barrel = add(g, new THREE.CylinderGeometry(0.0061, 0.0061, 0.06, 40, 1, true).translate(0, 0.0695, 0), M.clear, false);
      barrel.renderOrder = 3;
      const grad = add(g, new THREE.CylinderGeometry(0.00615, 0.00615, 0.058, 40, 1, true, -0.9, 1.8).translate(0, 0.0695, 0),
        keep(new THREE.MeshBasicMaterial({ map: tex(makeLabel('syringe')), transparent: true, depthWrite: false })), false);
      grad.renderOrder = 4;
      const flange = add(g, new THREE.BoxGeometry(0.028, 0.0016, 0.0105), M.clear, false); flange.position.y = 0.0997;
      const fluid = add(g, new THREE.CylinderGeometry(0.0055, 0.0055, 1, 28).translate(0, 0.5, 0), M.fluid, false);
      fluid.position.y = 0.0395; fluid.renderOrder = 2;
      const plunger = new THREE.Group(); g.add(plunger);
      add(plunger, lathe([[0, 0], [0.0054, 0], [0.0057, 0.0009], [0.0052, 0.0016], [0.0057, 0.0024], [0.0052, 0.0032], [0.0054, 0.004], [0, 0.0041]], 32), M.rubber);
      add(plunger, new THREE.BoxGeometry(0.0085, 0.07, 0.0011).translate(0, 0.039, 0), M.white);
      add(plunger, new THREE.BoxGeometry(0.0011, 0.07, 0.0085).translate(0, 0.039, 0), M.white);
      add(plunger, new THREE.CylinderGeometry(0.0078, 0.0078, 0.0016, 32).translate(0, 0.0745, 0), M.white);
      const api = {
        group: g, plunger: 0,
        set(p) {
          if (p.plunger !== undefined) {
            api.plunger = clamp(p.plunger, 0, 1);
            const y = lerp(0.094, 0.0405, api.plunger);
            plunger.position.y = y;
            fluid.scale.y = Math.max(0.0001, y - 0.0395);
          }
        },
      };
      api.set({ plunger: 0 });
      return api;
    }
    // loft an elliptical section along +Y: rows [{ y, w, t, x?, z? }] → smooth shaded tube with caps
    function loftRound(rows, seg = 12) {
      const g = new THREE.BufferGeometry(), pos = [], idx = [];
      rows.forEach(r => {
        for (let k = 0; k < seg; k++) {
          const a = (k / seg) * TAU;
          pos.push((r.x || 0) + Math.cos(a) * r.w / 2, r.y, (r.z || 0) + Math.sin(a) * r.t / 2);
        }
      });
      for (let i = 0; i < rows.length - 1; i++) for (let k = 0; k < seg; k++) {
        const a = i * seg + k, b = i * seg + ((k + 1) % seg), c = a + seg, d = b + seg;
        idx.push(a, d, b, a, c, d);
      }
      const n = pos.length / 3;
      const r0 = rows[0], r1 = rows[rows.length - 1];
      pos.push(r0.x || 0, r0.y, r0.z || 0, r1.x || 0, r1.y, r1.z || 0);
      for (let k = 0; k < seg; k++) {
        idx.push(n, k, (k + 1) % seg);
        const o = (rows.length - 1) * seg;
        idx.push(n + 1, o + (k + 1) % seg, o + k);
      }
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      g.setIndex(idx);
      g.computeVertexNormals();
      return g;
    }
    // 30 mL irrigation syringe with a blunt plastic tip; set({ plunger: 0 full → 1 empty })
    function buildIrrigator() {
      const g = new THREE.Group();
      add(g, new THREE.CylinderGeometry(0.00045, 0.0006, 0.022, 14).translate(0, 0.011, 0), M.white);
      add(g, lathe([[0.0006, 0.0215], [0.0019, 0.0225], [0.0021, 0.027], [0.0026, 0.0285], [0.0026, 0.0305], [0, 0.0305]], 24), M.teal);
      add(g, lathe([[0.0012, 0.0302], [0.0025, 0.031], [0.0104, 0.0355], [0.0108, 0.0362]], 40), M.clear, false);
      const barrel = add(g, new THREE.CylinderGeometry(0.0108, 0.0108, 0.076, 48, 1, true).translate(0, 0.074, 0), M.clear, false);
      barrel.renderOrder = 3;
      const grad = add(g, new THREE.CylinderGeometry(0.01088, 0.01088, 0.07, 48, 1, true, -0.95, 1.9).translate(0, 0.074, 0),
        keep(new THREE.MeshBasicMaterial({ map: tex(makeLabel('irrigator')), transparent: true, depthWrite: false })), false);
      grad.renderOrder = 4;
      const flange = add(g, new THREE.BoxGeometry(0.044, 0.0022, 0.017), M.clear, false); flange.position.y = 0.1125;
      const fluid = add(g, new THREE.CylinderGeometry(0.0101, 0.0101, 1, 32).translate(0, 0.5, 0), M.fluid, false);
      fluid.position.y = 0.0362; fluid.renderOrder = 2;
      const plunger = new THREE.Group(); g.add(plunger);
      add(plunger, lathe([[0, 0], [0.0102, 0], [0.0106, 0.0012], [0.0099, 0.0022], [0.0106, 0.0034], [0.0099, 0.0046], [0.0102, 0.0056], [0, 0.0058]], 40), M.rubber);
      add(plunger, new THREE.BoxGeometry(0.016, 0.084, 0.0016).translate(0, 0.047, 0), M.white);
      add(plunger, new THREE.BoxGeometry(0.0016, 0.084, 0.016).translate(0, 0.047, 0), M.white);
      add(plunger, new THREE.CylinderGeometry(0.0125, 0.0125, 0.0022, 40).translate(0, 0.0895, 0), M.white);
      const api = {
        group: g, plunger: 0,
        set(p) {
          if (p.plunger !== undefined) {
            api.plunger = clamp(p.plunger, 0, 1);
            const y = lerp(0.108, 0.0368, api.plunger);
            plunger.position.y = y;
            fluid.scale.y = Math.max(0.0001, y - 0.0362);
          }
        },
      };
      api.set({ plunger: 0 });
      return api;
    }
    function buildNeedleDriver() {
      const g = new THREE.Group(), r = 0.0058;
      // 3/8 curved needle: point at the origin, arc bulging to -X, swage end up
      const needle = add(g, new THREE.TorusGeometry(r, 0.00034, 8, 48, Math.PI * 0.75), M.steel);
      needle.position.set(-r, 0, 0);
      const grip = new THREE.Vector3(-r + r * Math.cos(1.9), r * Math.sin(1.9), 0);
      const jaw = new THREE.Group(); g.add(jaw);
      jaw.position.copy(grip);
      jaw.rotation.set(0.0, 0, -0.18);
      const halves = [];
      for (const sd of [-1, 1]) {
        const h = new THREE.Group(); jaw.add(h); halves.push(h);
        // serrated carbide jaw insert + tapered jaw
        add(h, loftRound([{ y: -0.0011, w: 0.0011, t: 0.0011, x: sd * 0.00045 }, { y: 0.0035, w: 0.0016, t: 0.0018, x: sd * 0.0007 }], 10), M.steelDark);
        add(h, loftRound([{ y: 0.0032, w: 0.0017, t: 0.0019, x: sd * 0.0007 }, { y: 0.009, w: 0.0024, t: 0.0028, x: sd * 0.001 }, { y: 0.0135, w: 0.0028, t: 0.0034, x: sd * 0.00115 }], 12), M.steel);
        // shank: flat bar that spreads toward the rings
        add(h, loftRound([
          { y: 0.016, w: 0.0026, t: 0.0034, x: sd * 0.0011 }, { y: 0.03, w: 0.0027, t: 0.0029, x: sd * 0.0016 },
          { y: 0.06, w: 0.0029, t: 0.0027, x: sd * 0.0031 }, { y: 0.09, w: 0.003, t: 0.0027, x: sd * 0.0052 },
          { y: 0.114, w: 0.0033, t: 0.0029, x: sd * 0.0074 },
        ], 14), M.steelSatin);
        // finger ring (gold = tungsten carbide jaws)
        const ring = add(h, new THREE.TorusGeometry(0.0082, 0.00155, 14, 40), M.gold);
        ring.position.set(sd * 0.0128, 0.1205, 0.0);
        ring.rotation.set(0, 0, sd * 0.22);
        // ratchet teeth
        for (let i = 0; i < 4; i++) {
          const t = add(h, new THREE.BoxGeometry(0.0016, 0.0011, 0.0018), M.steelSatin);
          t.position.set(sd * (0.0062 - 0.0011), 0.1035 + i * 0.0016, sd * 0.0006);
          t.rotation.z = sd * 0.6;
        }
      }
      // box lock: lens-shaped joint with a screw
      const lock = add(jaw, new THREE.CylinderGeometry(0.0026, 0.0026, 0.0038, 28).rotateX(Math.PI / 2), M.steelSatin);
      lock.scale.set(1, 1.4, 1); lock.position.set(0, 0.0148, 0);
      const screw = add(jaw, new THREE.CylinderGeometry(0.001, 0.001, 0.0041, 20).rotateX(Math.PI / 2), M.steel);
      screw.position.set(0, 0.0148, 0);
      const slot = add(jaw, new THREE.BoxGeometry(0.0015, 0.00024, 0.0043), M.steelDark, false);
      slot.position.set(0, 0.0148, 0); slot.rotation.z = 0.6;
      // braided suture from the swage end, trailing back along the instrument
      const sw = new THREE.Vector3(-r + r * Math.cos(Math.PI * 0.75), r * Math.sin(Math.PI * 0.75), 0);
      add(g, tube([sw, [sw.x - 0.003, sw.y + 0.0018, 0.0016], [sw.x - 0.009, sw.y + 0.0065, 0.0048], [sw.x - 0.016, sw.y + 0.015, 0.0062], [sw.x - 0.021, sw.y + 0.027, 0.0055]], 0.00024, 60, 6), M.thread);
      return {
        group: g,
        set(p) { if (p.open !== undefined) { halves[0].rotation.z = p.open * 0.1; halves[1].rotation.z = -p.open * 0.1; } },
      };
    }
    function buildForceps() {
      const g = new THREE.Group(), halves = [];
      for (const sd of [-1, 1]) {
        const h = new THREE.Group(); g.add(h); halves.push(h);
        add(h, loft([
          { y: 0, w: 0.0011, t: 0.0011, x: sd * 0.0007 }, { y: 0.008, w: 0.0016, t: 0.0014, x: sd * 0.001 },
          { y: 0.03, w: 0.0045, t: 0.0018, x: sd * 0.0032 }, { y: 0.075, w: 0.0075, t: 0.0019, x: sd * 0.0052 },
          { y: 0.11, w: 0.0075, t: 0.0019, x: sd * 0.0045 }, { y: 0.122, w: 0.006, t: 0.0019, x: sd * 0.002 },
        ]), M.steelSatin);
        for (let i = 0; i < 9; i++) { const rb = add(h, new THREE.BoxGeometry(0.0062, 0.0007, 0.0004), M.steelDark, false); rb.position.set(sd * 0.0052, 0.06 + i * 0.0035, 0.0011); }
      }
      add(g, new THREE.BoxGeometry(0.008, 0.008, 0.0024).translate(0, 0.122, 0), M.steelSatin);
      return { group: g, set(p) { if (p.open !== undefined) { halves[0].rotation.z = -p.open * 0.045; halves[1].rotation.z = p.open * 0.045; } } };
    }
    function buildScalpel() {
      const g = new THREE.Group();
      const sh = new THREE.Shape();
      sh.moveTo(0, 0); sh.quadraticCurveTo(-0.0055, 0.004, -0.0048, 0.014); sh.lineTo(-0.0012, 0.026); sh.lineTo(0.0022, 0.026);
      sh.lineTo(0.0022, 0.012); sh.quadraticCurveTo(0.0016, 0.004, 0, 0);
      add(g, new THREE.ExtrudeGeometry(sh, { depth: 0.0004, bevelEnabled: false }).translate(0, 0, -0.0002), M.steel);
      add(g, loft([{ y: 0.022, w: 0.004, t: 0.0026 }, { y: 0.03, w: 0.0085, t: 0.0028 }, { y: 0.06, w: 0.0095, t: 0.0028 }, { y: 0.135, w: 0.011, t: 0.0026 }, { y: 0.142, w: 0.008, t: 0.0024 }]), M.steelSatin);
      for (let i = 0; i < 14; i++) { const rb = add(g, new THREE.BoxGeometry(0.0085, 0.0011, 0.0006), M.steelDark, false); rb.position.set(0, 0.045 + i * 0.0032, 0.0015); }
      return { group: g, set() {} };
    }
    function buildProbe() {
      const g = new THREE.Group();
      add(g, new THREE.SphereGeometry(0.0011, 16, 12).translate(0, 0.0011, 0), M.steel);
      add(g, new THREE.CylinderGeometry(0.0007, 0.0007, 0.085, 12).translate(0, 0.044, 0), M.steel);
      add(g, lathe([[0.0007, 0.085], [0.0032, 0.092], [0.0034, 0.15], [0.0024, 0.155], [0, 0.156]], 24), M.steelSatin);
      return { group: g, set() {} };
    }
    function buildGauze() {
      const g = new THREE.Group();
      const weave = makeWeave({ threads: 14, seed: 11, fuzz: 0.6 });
      const cv2 = canvas(256, 256), c2 = cv2.getContext('2d');
      const redraw = stains => {
        c2.drawImage(weave.albedo, 0, 0);
        c2.fillStyle = 'rgba(255,255,255,.55)'; c2.fillRect(0, 0, 256, 256);
        stains.forEach(s => {
          const gr = c2.createRadialGradient(s.x * 256, s.y * 256, 0, s.x * 256, s.y * 256, s.r * 256);
          gr.addColorStop(0, `rgba(120,10,8,${0.85 * s.a})`); gr.addColorStop(0.7, `rgba(150,16,12,${0.6 * s.a})`); gr.addColorStop(1, 'rgba(160,20,16,0)');
          c2.fillStyle = gr; c2.beginPath(); c2.arc(s.x * 256, s.y * 256, s.r * 256, 0, TAU); c2.fill();
        });
      };
      const stains = [];
      redraw(stains);
      const t = tex(cv2);
      const nt = tex(weave.normal, false); nt.wrapS = nt.wrapT = THREE.RepeatWrapping; nt.repeat.set(3, 3);
      const mat = keep(new THREE.MeshPhysicalMaterial({ map: t, normalMap: nt, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.95, sheen: 0.7, sheenColor: new THREE.Color(1, 1, 1), sheenRoughness: 0.7 }));
      const bg = new THREE.BoxGeometry(0.05, 0.0045, 0.05, 10, 2, 10);
      const p = bg.attributes.position;
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
        const ex = Math.abs(x) / 0.025, ez = Math.abs(z) / 0.025, e = Math.max(ex, ez);
        p.setY(i, y * (1 - Math.pow(e, 6) * 0.55) + (noiseAt(0, x * 40 + 2, z * 40) - 0.5) * 0.0012);
      }
      bg.computeVertexNormals();
      const pad = add(g, bg.translate(0, 0.00225, 0), mat);
      return {
        group: g, stains,
        set(q) {
          if (q.squash !== undefined) pad.scale.y = 1 - q.squash * 0.45;
          if (q.stain) { stains.push(q.stain); redraw(stains); t.needsUpdate = true; }
          if (q.fresh) { stains.length = 0; redraw(stains); t.needsUpdate = true; }
        },
      };
    }
    function buildStapler() {
      const g = new THREE.Group();
      add(g, loft([{ y: 0, w: 0.009, t: 0.004, z: 0.001 }, { y: 0.012, w: 0.016, t: 0.012, z: 0.004 }, { y: 0.03, w: 0.026, t: 0.022, z: 0.008 }, { y: 0.1, w: 0.03, t: 0.026, z: 0.009 }, { y: 0.112, w: 0.024, t: 0.02, z: 0.008 }]), M.white);
      const lab = add(g, new THREE.PlaneGeometry(0.026, 0.05), keep(new THREE.MeshPhysicalMaterial({ map: tex(makeLabel('stapler')), roughness: 0.4, clearcoat: 0.6 })));
      lab.position.set(0, 0.065, 0.0221);
      add(g, loft([{ y: 0.03, w: 0.016, t: 0.006, z: -0.006 }, { y: 0.09, w: 0.018, t: 0.008, z: -0.012 }]), M.teal);
      add(g, new THREE.BoxGeometry(0.008, 0.0016, 0.003).translate(0, 0.0008, 0.001), M.steel);
      return { group: g, set() {} };
    }
    function buildDermatome() {
      const g = new THREE.Group();
      add(g, new THREE.BoxGeometry(0.075, 0.0014, 0.012).translate(0, 0.0007, 0), M.steel);
      add(g, loft([{ y: 0.0014, w: 0.078, t: 0.016 }, { y: 0.02, w: 0.06, t: 0.03 }, { y: 0.035, w: 0.034, t: 0.034 }]), M.steelSatin);
      add(g, new THREE.CylinderGeometry(0.018, 0.017, 0.15, 36).translate(0, 0.11, 0), M.white);
      add(g, new THREE.CylinderGeometry(0.0184, 0.0184, 0.012, 36).translate(0, 0.06, 0), M.teal);
      add(g, new THREE.CylinderGeometry(0.0075, 0.009, 0.02, 24).translate(0, 0.195, 0), M.dark);
      return { group: g, set() {} };
    }
    const BUILD = { saline: buildSaline, irrigator: buildIrrigator, syringe: buildSyringe, needleDriver: buildNeedleDriver, forceps: buildForceps, scalpel: buildScalpel, probe: buildProbe, gauze: buildGauze, stapler: buildStapler, dermatome: buildDermatome };
    // lift: tip distance from the aim point along the tool axis · tilt: from the surface normal (rad)
    // yaw: screen angle of the handle (0 = right, π/2 = up) · roll: spin about the axis
    const POSE = {
      saline:       { lift: 0.045, pressLift: 0.045, tilt: 0.58, yaw: 1.85, roll: 0.0, shadow: 0.02 },
      irrigator:    { lift: 0.012, pressLift: 0.012, tilt: 1.0, yaw: 0.95, roll: 0.0, shadow: 0.014 },
      syringe:      { lift: 0.008, pressLift: -0.0038, tilt: 1.05, yaw: 0.45, roll: 0.0, shadow: 0.01 },
      needleDriver: { lift: 0.004, pressLift: -0.0012, tilt: 0.85, yaw: 0.8, roll: 0.5, shadow: 0.016 },
      forceps:      { lift: 0.006, pressLift: 0.0, tilt: 0.55, yaw: 1.25, roll: 0, shadow: 0.012 },
      scalpel:      { lift: 0.006, pressLift: -0.0008, tilt: 0.9, yaw: 0.65, roll: 0, shadow: 0.012 },
      probe:        { lift: 0.006, pressLift: -0.002, tilt: 0.45, yaw: 1.4, roll: 0, shadow: 0.008 },
      gauze:        { lift: 0.016, pressLift: 0.0004, tilt: 0.0, yaw: 0, roll: 0, shadow: 0.05 },
      stapler:      { lift: 0.008, pressLift: 0.0008, tilt: 0.7, yaw: 1.3, roll: 0, shadow: 0.03 },
      dermatome:    { lift: 0.012, pressLift: 0.0005, tilt: 0.95, yaw: 1.57, roll: 0, shadow: 0.07 },
    };
    const blob = new THREE.Mesh(geo(new THREE.PlaneGeometry(1, 1)), keep(new THREE.MeshBasicMaterial({ map: tex(makeMarkerSprite('soft'), false), color: 0x000000, transparent: true, depthWrite: false, opacity: 0, polygonOffset: true, polygonOffsetFactor: -2 })));
    blob.renderOrder = 1;
    scene.add(blob);
    const toolCache = {};
    const tools = {
      active: null, follow: true, hit: null, pressed: false, hovering: true,
      get(name) {
        if (toolCache[name]) return toolCache[name];
        const b = BUILD[name];
        if (!b) return null;
        const t = b();
        t.name = name;
        t.pose = Object.assign({}, POSE[name]);
        t.press = 0;
        t.group.visible = false;
        t.group.traverse(c => { if (c.isMesh) c.castShadow = c.castShadow !== false; });
        t.tipWorld = () => t.group.getWorldPosition(new THREE.Vector3());
        t._p = new THREE.Vector3(); t._q = new THREE.Quaternion(); t._init = false;
        scene.add(t.group);
        toolCache[name] = t;
        return t;
      },
      use(name, poseOpts) {
        if (tools.active) tools.active.group.visible = false;
        if (!name) { tools.active = null; blob.material.opacity = 0; return null; }
        const t = typeof name === 'string' ? tools.get(name) : name;
        if (!t) return null;
        if (poseOpts) Object.assign(t.pose, poseOpts);
        t._init = false;
        tools.active = t;
        return t;
      },
      press(v) { tools.pressed = !!v; },
      hover(v) { tools.hovering = !!v; },
    };
    S.tools = tools;
    const _tq = new THREE.Quaternion(), _tm = new THREE.Matrix4(), _cr = new THREE.Vector3(), _cu = new THREE.Vector3(), _bn = new THREE.Vector3(), _bp = new THREE.Vector3();
    function poseTool(t, hit, dt, instant) {
      const pz = t.pose;
      t.press = lerp(t.press, tools.pressed ? 1 : 0, 1 - Math.exp(-dt * 16));
      const lift = lerp(pz.lift, pz.pressLift, t.press);
      // handle direction: screen angle → tangent plane of the hit normal
      _cr.setFromMatrixColumn(camera.matrixWorld, 0); _cu.setFromMatrixColumn(camera.matrixWorld, 1);
      const sd = new THREE.Vector3().addScaledVector(_cr, Math.cos(pz.yaw)).addScaledVector(_cu, Math.sin(pz.yaw));
      // orient by the smooth body surface, not the local wound relief (groove walls are steep)
      const n = _bn;
      surf(hit.s !== undefined ? hit.s : 0, hit.t !== undefined ? hit.t : 0, _bp, n);
      n.lerp(hit.normal, 0.15).normalize();
      sd.addScaledVector(n, -sd.dot(n));
      if (sd.lengthSq() < 1e-8) sd.set(1, 0, 0);
      sd.normalize();
      const axis = new THREE.Vector3().addScaledVector(n, Math.cos(pz.tilt)).addScaledVector(sd, Math.sin(pz.tilt)).normalize();
      const xA = new THREE.Vector3().crossVectors(axis, n);
      if (xA.lengthSq() < 1e-8) xA.crossVectors(axis, sd);
      xA.normalize();
      const zA = new THREE.Vector3().crossVectors(xA, axis).normalize();
      _tm.makeBasis(xA, axis, zA);
      _tq.setFromRotationMatrix(_tm);
      if (pz.roll) _tq.multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), pz.roll));
      const target = hit.point.clone().addScaledVector(axis, lift);
      if (instant || !t._init) { t._p.copy(target); t._q.copy(_tq); t._init = true; }
      else { const k = 1 - Math.exp(-dt * 30); t._p.lerp(target, k); t._q.slerp(_tq, k); }
      t.group.position.copy(t._p); t.group.quaternion.copy(t._q);
      // contact occlusion: only a faint darkening right under a tool that touches the skin
      // (the lamp's soft shadow map does the rest)
      const h = Math.max(0, lift);
      const sz = (pz.shadow || 0.012) * (0.55 + h * 18);
      blob.position.copy(hit.point).addScaledVector(n, 0.0002);
      blob.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), n);
      blob.scale.set(sz, sz, 1);
      blob.material.opacity = 0.3 * (1 - smooth(0.0, 0.012, h));
    }
    function updateTools(dt) {
      const t = tools.active;
      if (!t) return;
      if (tools.follow) {
        const hit = raycast(S.pointer);
        if (hit) { tools.hit = hit; t.group.visible = tools.hovering; poseTool(t, hit, dt); }
        else { t.group.visible = false; blob.material.opacity = 0; }
      } else if (tools.hit) poseTool(t, tools.hit, dt);
      blob.visible = t.group.visible;
      if (t.update) t.update(dt);
    }
    tools.poseAt = (t, hit, instant) => poseTool(t, hit, 0.016, instant);

    /* ═════════════ MARKERS ═════════════ */
    const markerGeo = geo(new THREE.PlaneGeometry(1, 1));
    const pinGeo = geo(new THREE.ConeGeometry(0.0017, 0.0048, 20).rotateX(Math.PI).translate(0, 0.0024, 0));
    const pinCap = geo(new THREE.SphereGeometry(0.0019, 20, 14));
    const markerTex = {};
    const markerMap = {};
    const markers = {
      set(id, d) {
        let mk = markerMap[id];
        const kind = d.kind || (mk && mk.kind) || 'ring';
        if (mk && mk.kind !== kind) { markers.remove(id); mk = null; }
        if (!mk) {
          if (kind === 'pin') {
            const mat = keep(new THREE.MeshBasicMaterial({ color: 0x0fd4c4, toneMapped: false, transparent: true }));
            const grp = new THREE.Group();
            grp.add(new THREE.Mesh(pinGeo, mat)); const cap = new THREE.Mesh(pinCap, mat); cap.position.y = 0.0058; grp.add(cap);
            mk = { kind, obj: grp, mat };
          } else {
            const spriteKind = kind;
            if (!markerTex[spriteKind]) markerTex[spriteKind] = tex(makeMarkerSprite(spriteKind), false);
            const mat = keep(new THREE.MeshBasicMaterial({ map: markerTex[spriteKind], color: 0x0fd4c4, transparent: true, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -6 }));
            const me = new THREE.Mesh(markerGeo, mat); me.renderOrder = 5;
            mk = { kind, obj: me, mat };
          }
          scene.add(mk.obj);
          markerMap[id] = mk;
        }
        Object.assign(mk, { uv: d.uv !== undefined ? uvOf(d.uv) : mk.uv, size: d.size !== undefined ? d.size : (mk.size || 0.006),
          color: d.color !== undefined ? d.color : (mk.color !== undefined ? mk.color : 0x0fd4c4), opacity: d.opacity !== undefined ? d.opacity : (mk.opacity !== undefined ? mk.opacity : 1),
          pulse: d.pulse !== undefined ? d.pulse : mk.pulse !== undefined ? mk.pulse : true, lift: d.lift !== undefined ? d.lift : (mk.lift || 0.007) });
        mk.mat.color.set(mk.color);
        const sp = S.surfaceAt(mk.uv);
        mk.point = sp.point; mk.normal = sp.normal;
        mk.obj.visible = d.visible !== false;
        return mk;
      },
      get(id) { return markerMap[id] || null; },
      remove(id) { const mk = markerMap[id]; if (!mk) return; scene.remove(mk.obj); delete markerMap[id]; },
      clear() { Object.keys(markerMap).forEach(markers.remove); },
    };
    S.markers = markers;
    function updateMarkers(time) {
      for (const id in markerMap) {
        const mk = markerMap[id];
        if (!mk.point) continue;
        const pulse = mk.pulse ? 1 + Math.sin(time * 4.2) * 0.08 : 1;
        if (mk.kind === 'pin') {
          const bob = Math.sin(time * 3.2) * 0.0012;
          mk.obj.position.copy(mk.point).addScaledVector(mk.normal, mk.lift + bob);
          mk.obj.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), mk.normal);
          mk.obj.scale.setScalar(mk.size / 0.006);
        } else {
          mk.obj.position.copy(mk.point).addScaledVector(mk.normal, 0.00035);
          mk.obj.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), mk.normal);
          mk.obj.scale.set(mk.size * pulse, mk.size * pulse, 1);
        }
        mk.mat.opacity = mk.opacity * (mk.pulse ? 0.82 + Math.sin(time * 4.2) * 0.18 : 1);
      }
    }

    /* ═════════════ STITCHES ═════════════ */
    const stitchList = [];
    const knotGeo = geo(new THREE.SphereGeometry(0.00042, 10, 8));
    const knotRing = geo(new THREE.TorusGeometry(0.00052, 0.00022, 6, 16));
    function stitchPoints(aUv, bUv) {
      const A = S.surfaceAt(aUv), B = S.surfaceAt(bUv);
      const n = A.normal.clone().add(B.normal).normalize();
      return { A, B, n };
    }
    const stitches = {
      add(d) {
        const { A, B, n } = stitchPoints(d.a, d.b);
        const R = rng(d.seed !== undefined ? d.seed : stitchList.length * 977 + 13);
        const knotAtA = d.knot !== 'b';
        const P = knotAtA ? A : B, Q = knotAtA ? B : A;
        const Pin = P.point.clone().addScaledVector(P.normal, -0.0006), Pout = P.point.clone().addScaledVector(P.normal, 0.0003);
        const Qin = Q.point.clone().addScaledVector(Q.normal, -0.0006), Qout = Q.point.clone().addScaledVector(Q.normal, 0.0003);
        const K = P.point.clone().lerp(Q.point, 0.17).addScaledVector(n, 0.00075);
        const Mid = P.point.clone().lerp(Q.point, 0.58).addScaledVector(n, 0.00048);
        const grp = new THREE.Group();
        const rad = d.radius || 0.0002;
        const mat = d.color !== undefined ? keep(new THREE.MeshPhysicalMaterial({ color: d.color, roughness: 0.32, clearcoat: 0.9 })) : M.thread;
        add(grp, tube([Pin, Pout, K, Mid, Qout, Qin], rad, 48, 7), mat);
        // knot
        for (let i = 0; i < 3; i++) {
          const k = new THREE.Mesh(knotGeo, mat); k.castShadow = true;
          k.position.copy(K).add(new THREE.Vector3((R() - 0.5) * 0.0008, (R() - 0.5) * 0.0003, (R() - 0.5) * 0.0008));
          k.scale.setScalar(0.85 + R() * 0.5); grp.add(k);
        }
        const kr = new THREE.Mesh(knotRing, mat); kr.position.copy(K); kr.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), n); kr.castShadow = true; grp.add(kr);
        // tails, roughly along the wound
        const across = Q.point.clone().sub(P.point).normalize();
        const along = new THREE.Vector3().crossVectors(n, across).normalize();
        for (const sgn of [1, -1]) {
          const dir = along.clone().multiplyScalar(sgn).addScaledVector(across, -0.55 - R() * 0.5).normalize();
          const L = 0.0024 + R() * 0.0018;
          const side = new THREE.Vector3().crossVectors(n, dir).multiplyScalar((R() - 0.5) * 0.0016);
          const p1 = K.clone().addScaledVector(dir, L * 0.5).add(side).addScaledVector(n, 0.0004);
          const p2 = K.clone().addScaledVector(dir, L).add(side.clone().multiplyScalar(1.8)).addScaledVector(n, 0.00022);
          add(grp, tube([K, p1, p2], rad * 0.92, 12, 6), mat);
        }
        scene.add(grp);
        const st = { group: grp, a: uvOf(d.a), b: uvOf(d.b), sa: uvToST(d.a), sb: uvToST(d.b), remove() { scene.remove(grp); grp.traverse(c => { if (c.isMesh && c.geometry !== knotGeo && c.geometry !== knotRing) { c.geometry.dispose(); bin.delete(c.geometry); } }); const i = stitchList.indexOf(st); if (i >= 0) stitchList.splice(i, 1); } };
        stitchList.push(st);
        return st;
      },
      preview(aUv, to) {
        if (stitches._pv) { scene.remove(stitches._pv); stitches._pv.geometry.dispose(); bin.delete(stitches._pv.geometry); stitches._pv = null; }
        if (!aUv || !to) return;
        const A = S.surfaceAt(aUv);
        const T2 = to.isVector3 ? to.clone() : S.surfaceAt(to).point;
        const Ain = A.point.clone().addScaledVector(A.normal, -0.0007), Aout = A.point.clone().addScaledVector(A.normal, 0.0004);
        const mid = Aout.clone().lerp(T2, 0.5).addScaledVector(A.normal, 0.0012 + Aout.distanceTo(T2) * 0.08);
        const me = new THREE.Mesh(geo(tube([Ain, Aout, mid, T2], 0.00027, 28, 6)), M.thread);
        me.castShadow = true;
        scene.add(me);
        stitches._pv = me;
      },
      clear() { while (stitchList.length) stitchList[0].remove(); stitches.preview(null); },
      get list() { return stitchList.slice(); },
    };
    S.stitches = stitches;
    // how high stitches stand off the skin at patch point (s, t) — cloth rests on top of them
    function stitchClear(s, t) {
      let c = 0;
      for (let i = 0; i < stitchList.length; i++) {
        const a = stitchList[i].sa, b = stitchList[i].sb;
        const abx = b[0] - a[0], aby = b[1] - a[1], l2 = abx * abx + aby * aby || 1e-12;
        const f = clamp(((s - a[0]) * abx + (t - a[1]) * aby) / l2, 0, 1);
        const d = Math.hypot(s - a[0] - abx * f, t - a[1] - aby * f);
        if (d < 0.0016) c = Math.max(c, 0.001 * (1 - d / 0.0016));
      }
      return c;
    }

    /* ═════════════ FLUIDS ═════════════ */
    const NP = Q.particles;
    const pGeo = geo(new THREE.BufferGeometry());
    const pPos = new Float32Array(NP * 3), pSize = new Float32Array(NP), pAlpha = new Float32Array(NP), pCol = new Float32Array(NP * 3);
    const pVel = new Float32Array(NP * 3), pLife = new Float32Array(NP), pMax = new Float32Array(NP), pKind = new Uint8Array(NP);
    pGeo.setAttribute('position', new THREE.BufferAttribute(pPos, 3).setUsage(THREE.DynamicDrawUsage));
    pGeo.setAttribute('aSize', new THREE.BufferAttribute(pSize, 1).setUsage(THREE.DynamicDrawUsage));
    pGeo.setAttribute('aAlpha', new THREE.BufferAttribute(pAlpha, 1).setUsage(THREE.DynamicDrawUsage));
    pGeo.setAttribute('aCol', new THREE.BufferAttribute(pCol, 3).setUsage(THREE.DynamicDrawUsage));
    const pMat = keep(new THREE.ShaderMaterial({
      uniforms: { tDrop: { value: tex(makeDropSprite(), false) }, uScale: { value: 600 } },
      vertexShader: PART_VERT, fragmentShader: PART_FRAG, transparent: true, depthWrite: false,
    }));
    const points = new THREE.Points(pGeo, pMat);
    points.frustumCulled = false; points.renderOrder = 8;
    scene.add(points);
    let pNext = 0;
    function spawn(kind, x, y, z, vx, vy, vz, life, size, col, alpha) {
      let i = -1;
      for (let k = 0; k < NP; k++) { const j = (pNext + k) % NP; if (pLife[j] <= 0) { i = j; break; } }
      if (i < 0) i = pNext;
      pNext = (i + 1) % NP;
      pPos[i * 3] = x; pPos[i * 3 + 1] = y; pPos[i * 3 + 2] = z;
      pVel[i * 3] = vx; pVel[i * 3 + 1] = vy; pVel[i * 3 + 2] = vz;
      pLife[i] = life; pMax[i] = life; pKind[i] = kind; pSize[i] = size; pAlpha[i] = alpha;
      pCol[i * 3] = col[0]; pCol[i * 3 + 1] = col[1]; pCol[i * 3 + 2] = col[2];
    }
    const WATER = [0.86, 0.94, 1.0], BLOODC = [0.42, 0.02, 0.02];
    const jetMat = keep(new THREE.ShaderMaterial({
      uniforms: { p0: { value: new THREE.Vector3() }, p1: { value: new THREE.Vector3() }, p2: { value: new THREE.Vector3() }, uRadius: { value: 0.0011 }, uTime: { value: 0 }, uAlpha: { value: 0 } },
      vertexShader: JET_VERT, fragmentShader: JET_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide,
    }));
    const jetMesh = new THREE.Mesh(geo(new THREE.CylinderGeometry(1, 1, 1, 14, 40, true)), jetMat);
    jetMesh.frustumCulled = false; jetMesh.renderOrder = 7; jetMesh.visible = false;
    scene.add(jetMesh);
    const jet = { on: false, from: new THREE.Vector3(), to: new THREE.Vector3(), hit: null, wash: { grime: 1.2, blood: 0.8, clot: 0.15, soot: 0.5 }, wet: 1, rate: 1, radius: 0.006, flow: 0 };
    const impactFns = [];
    const oozes = new Map();
    const rivulets = [];
    const G = (() => { const g = o.gravity || [0, 1], l = Math.hypot(g[0], g[1]) || 1; return [g[0] / l, g[1] / l]; })();
    const fluids = {
      jet(d) {
        if (d === false || (d && d.on === false)) { jet.on = false; return; }
        jet.on = true;
        if (d.from) jet.from.copy(d.from);
        if (d.to) { if (d.to.point) { jet.to.copy(d.to.point); jet.hit = d.to; } else { jet.to.copy(d.to); jet.hit = null; } }
        if (d.wash) jet.wash = d.wash;
        if (d.wet !== undefined) jet.wet = d.wet;
        if (d.rate !== undefined) jet.rate = d.rate;
        if (d.radius !== undefined) jet.radius = d.radius;
        if (d.stream !== undefined) jet.stream = d.stream;
      },
      onImpact(fn) { impactFns.push(fn); return fn; },
      bleed(w, mlPerMin) { if (!w) return; if (mlPerMin > 0) oozes.set(w, { rate: mlPerMin, acc: 0, pool: 0 }); else oozes.delete(w); },
      drip(uv, vol = 0.12, dir) {
        if (rivulets.length > 14) return;
        const st = uvToST(uv);
        rivulets.push({ s: st[0], t: st[1], vol: Math.min(vol, 0.12), dir: dir || G.slice(), ph: Math.random() * 10 });
      },
      drops(point, count = 8, color = BLOODC, speed = 0.3) {
        for (let i = 0; i < count; i++) {
          const a = Math.random() * TAU, sp = speed * (0.4 + Math.random() * 0.8);
          spawn(2, point.x, point.y, point.z, Math.cos(a) * sp * 0.6, sp, Math.sin(a) * sp * 0.6, 0.35 + Math.random() * 0.4, 0.0011 + Math.random() * 0.0012, color, 0.95);
        }
      },
      clear() { pLife.fill(0); rivulets.length = 0; oozes.clear(); jet.on = false; },
      get flowing() { return jet.on; },
    };
    S.fluids = fluids;
    const _jp = new THREE.Vector3(), _jn = new THREE.Vector3();
    function updateFluids(dt) {
      const slow = 0.35;
      // jet core + splashes + washing
      jet.flow = lerp(jet.flow, jet.on ? 1 : 0, 1 - Math.exp(-dt * (jet.on ? 22 : 9)));
      jetMesh.visible = jet.flow > 0.02;
      if (jetMesh.visible) {
        const p0 = jetMat.uniforms.p0.value.copy(jet.from), p2 = jetMat.uniforms.p2.value.copy(jet.to);
        const L = p0.distanceTo(p2);
        jetMat.uniforms.p1.value.copy(p0).lerp(p2, 0.5).add(new THREE.Vector3(0, -L * 0.06, 0));
        jetMat.uniforms.uTime.value += dt;
        jetMat.uniforms.uAlpha.value = jet.flow;
        jetMat.uniforms.uRadius.value = jet.stream || (0.00045 + 0.00025 * jet.rate);
      }
      if (jet.on) {
        const q = toSurf(jet.to);
        const hit = jet.hit || surfaceAtST(q.s, q.t, {});
        const uvh = stToUv(q.s, q.t);
        const n = hit.normal || _jn.set(0, 1, 0);
        const r = jet.radius, k = dt * jet.rate;
        if (jet.wash) for (const name in jet.wash) if (CH[name] && jet.wash[name] > 0) layers.erase(name, uvh, r, jet.wash[name] * k, { hardness: 0.15 });
        // runoff carries a little further down the slope
        const ru = stToUv(q.s + G[0] * r * 1.6, q.t + G[1] * r * 1.6);
        if (jet.wash) for (const name in jet.wash) if (CH[name] && jet.wash[name] > 0) layers.erase(name, ru, [r * 1.1, r * 1.6], jet.wash[name] * k * 0.35, { hardness: 0.1, angle: Math.atan2(G[1], G[0]) + Math.PI / 2 });
        if (jet.wet > 0) { layers.paint('wet', uvh, r * 2.2, k * 2.2 * jet.wet, { hardness: 0.1 }); layers.paint('wet', ru, r * 2.6, k * 1.2 * jet.wet, { hardness: 0.1 }); }
        const nSplash = Math.min(14, Math.ceil(dt * 260 * jet.rate));
        for (let i = 0; i < nSplash; i++) {
          const a = Math.random() * TAU, sp = 0.05 + Math.random() * 0.16;
          const t1 = new THREE.Vector3(Math.cos(a), 0, Math.sin(a));
          t1.addScaledVector(n, -t1.dot(n)).normalize();
          spawn(1, hit.point.x, hit.point.y + 0.0006, hit.point.z, t1.x * sp + n.x * sp * 1.3, t1.y * sp + n.y * sp * 1.3, t1.z * sp + n.z * sp * 1.3, 0.12 + Math.random() * 0.22, 0.00025 + Math.random() * 0.0005, WATER, 0.75);
        }
        // a few droplets along the stream
        for (let i = 0; i < 3; i++) {
          const f = Math.random();
          _jp.copy(jet.from).lerp(jet.to, f);
          spawn(0, _jp.x + (Math.random() - 0.5) * 0.0008, _jp.y, _jp.z + (Math.random() - 0.5) * 0.0008, 0, -0.05, 0, 0.05 + Math.random() * 0.06, 0.0003 + Math.random() * 0.0003, WATER, 0.5);
        }
        for (const fn of impactFns) { try { fn(hit, dt, uvh); } catch (e) { console.error(e); } }
      }
      // particles
      const g = 9.8 * slow * slow;
      for (let i = 0; i < NP; i++) {
        if (pLife[i] <= 0) { pAlpha[i] = 0; continue; }
        pLife[i] -= dt;
        pVel[i * 3 + 1] -= g * dt;
        pPos[i * 3] += pVel[i * 3] * dt * slow; pPos[i * 3 + 1] += pVel[i * 3 + 1] * dt * slow; pPos[i * 3 + 2] += pVel[i * 3 + 2] * dt * slow;
        if (pKind[i] !== 0) {
          _jp.set(pPos[i * 3], pPos[i * 3 + 1], pPos[i * 3 + 2]);
          const q = toSurf(_jp);
          if (Math.abs(q.s) < W / 2 && Math.abs(q.t) < H / 2 && q.h < heightAt(q.s, q.t)) {
            if (pKind[i] === 2) layers.paint('blood', stToUv(q.s, q.t), 0.0004 + pSize[i] * 0.3, 0.36, { hardness: 0.45, grain: 0.35, grainScale: 220 });
            pLife[i] = 0;
          }
        }
        pAlpha[i] = pLife[i] > 0 ? Math.min(1, pLife[i] / (pMax[i] * 0.4)) * (pKind[i] === 2 ? 0.95 : 0.75) : 0;
      }
      pGeo.attributes.position.needsUpdate = true; pGeo.attributes.aAlpha.needsUpdate = true;
      pGeo.attributes.aSize.needsUpdate = true; pGeo.attributes.aCol.needsUpdate = true;
      // ooze from wounds
      oozes.forEach((oz, w) => {
        if (!woundList.includes(w)) { oozes.delete(w); return; }
        oz.acc += oz.rate * dt * 1.4;
        let guard = 0;
        while (oz.acc >= 1 && guard++ < 12) {
          oz.acc -= 1;
          if (w.code === 1) {
            let tN = Math.random(), tries = 0;
            while (tries++ < 6 && (w.envelope(tN) < 0.2 || Math.random() < w.closureAt(tN) * 0.92)) tN = Math.random();
            const hg = Math.max(w.halfGape(tN), 0.0007);
            const r = w.at(tN), off = (Math.random() * 2 - 1) * hg * 0.8;
            const uvp = stToUv(r.s + r.nrm[0] * off, r.t + r.nrm[1] * off);
            layers.paint('blood', uvp, [0.0012 + Math.random() * 0.0016, 0.0009 + Math.random() * 0.001], 0.2 + Math.random() * 0.15, { hardness: 0.3, grain: 0.3, grainScale: 160, angle: Math.atan2(r.dir[1], r.dir[0]) });
            oz.pool += 1;
            // the groove overflows → a rivulet runs down the slope
            if (oz.pool > 26 + w.length * 600 && Math.random() < 0.12) {
              oz.pool *= 0.45;
              const side = (r.nrm[0] * G[0] + r.nrm[1] * G[1]) >= 0 ? 1 : -1;
              fluids.drip(w.edge(tN, side, 0.0006), 0.04 + Math.random() * 0.06);
            }
          } else {
            const c = w.center, rad = (w.p.radius || 0.004) * w.p.open;
            const a = Math.random() * TAU, d = Math.random() * rad * 0.8;
            layers.paint('blood', stToUv(c[0] + Math.cos(a) * d, c[1] + Math.sin(a) * d), 0.0015, 0.28, { hardness: 0.3, grain: 0.3 });
            oz.pool += 1;
            if (oz.pool > 12 && Math.random() < 0.2) { oz.pool *= 0.7; fluids.drip(stToUv(c[0] + G[0] * rad * 1.2, c[1] + G[1] * rad * 1.2), 0.1); }
          }
        }
      });
      // rivulets
      for (let i = rivulets.length - 1; i >= 0; i--) {
        const rv = rivulets[i];
        const sp = 0.0045 * dt;
        rv.ph += dt * 2.4;
        const wob = (noiseAt(0, rv.ph * 0.3, rv.s * 40) - 0.5) * 1.1;
        const dx = rv.dir[0] + -rv.dir[1] * wob, dy = rv.dir[1] + rv.dir[0] * wob, l = Math.hypot(dx, dy) || 1;
        const ns = rv.s + (dx / l) * sp, nt = rv.t + (dy / l) * sp;
        // a trickle: thin film that narrows as it runs out, ending in a small bead
        const rad = 0.00028 + Math.max(0, rv.vol) * 0.0036;
        layers.stroke('blood', stToUv(rv.s, rv.t), stToUv(ns, nt), rad, 0.16, { hardness: 0.6 });
        rv.s = ns; rv.t = nt;
        rv.vol -= sp * 9;
        if (rv.vol <= 0 || Math.abs(ns) > W / 2 || Math.abs(nt) > H / 2) {
          if (rv.vol <= 0) layers.paint('blood', stToUv(ns, nt), 0.0009, 0.42, { hardness: 0.5 });
          rivulets.splice(i, 1);
        }
      }
    }

    /* ═════════════ DRESSING (cloth) ═════════════ */
    const dressings = [];
    function createDressing(d = {}) {
      const w = (d.size && d.size[0]) || 0.09, h = (d.size && d.size[1]) || 0.06;
      const pw = (d.pad && d.pad[0]) || w * 0.62, ph = (d.pad && d.pad[1]) || h * 0.5;
      const NX = 32, NY = Math.max(10, Math.round(32 * h / w)), N = NX * NY;
      const thick = 0.0005, padH = 0.0014;
      const pos = new Float32Array(N * 3), prev = new Float32Array(N * 3), rend = new Float32Array(N * 3), nrm = new Float32Array(N * 3);
      const stick = new Float32Array(N), stuck = new Uint8Array(N), pinned = new Uint8Array(N), contact = new Uint8Array(N);
      const padMask = new Float32Array(N), wgt = new Float32Array(N), local = new Float32Array(N * 2);
      const pinOff = new Float32Array(N * 3), carryW = new Float32Array(N);
      const c0 = uvToST(d.uv || [0.5, 0.5]), ang = d.angle || 0, ca = Math.cos(ang), sa = -Math.sin(ang);
      const P = new THREE.Vector3(), Nn = new THREE.Vector3();
      for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
        const k = j * NX + i;
        const lx = (i / (NX - 1) - 0.5) * w, ly = (j / (NY - 1) - 0.5) * h;
        local[k * 2] = lx; local[k * 2 + 1] = ly;
        const s = c0[0] + lx * ca - ly * sa, t = c0[1] + lx * sa + ly * ca;
        surf(s, t, P, Nn);
        // a fresh dressing out of its pack curls up a little at the edges
        const ex = Math.abs(lx) / (w / 2), ey = Math.abs(ly) / (h / 2);
        const curl = (Math.pow(Math.max(ex, ey), 3) * 0.0016 + Math.pow(ex * ey, 2) * 0.0012) * (d.curl !== undefined ? d.curl : 1);
        P.addScaledVector(Nn, heightAt(s, t) + thick + curl);
        pos[k * 3] = prev[k * 3] = P.x; pos[k * 3 + 1] = prev[k * 3 + 1] = P.y; pos[k * 3 + 2] = prev[k * 3 + 2] = P.z;
        const m = smooth(-0.0015, 0.0015, pw / 2 - Math.abs(lx)) * smooth(-0.0015, 0.0015, ph / 2 - Math.abs(ly));
        padMask[k] = m;
        wgt[k] = m > 0.5 ? 1 : 1.6;
      }
      // constraints [a, b, rest, stiffness]
      const cons = [];
      const link = (a, b, kf) => {
        const dx = pos[a * 3] - pos[b * 3], dy = pos[a * 3 + 1] - pos[b * 3 + 1], dz = pos[a * 3 + 2] - pos[b * 3 + 2];
        cons.push(a, b, Math.hypot(dx, dy, dz), kf);
      };
      for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
        const k = j * NX + i;
        if (i < NX - 1) link(k, k + 1, 1);
        if (j < NY - 1) link(k, k + NX, 1);
        if (i < NX - 1 && j < NY - 1) { link(k, k + NX + 1, 0.6); link(k + 1, k + NX, 0.6); }
        if (i < NX - 2) link(k, k + 2, padMask[k] > 0.5 ? 0.5 : 0.12);
        if (j < NY - 2) link(k, k + 2 * NX, padMask[k] > 0.5 ? 0.5 : 0.12);
      }
      const consArr = Float32Array.from(cons);
      const g2 = geo(new THREE.BufferGeometry());
      g2.setAttribute('position', new THREE.BufferAttribute(rend, 3).setUsage(THREE.DynamicDrawUsage));
      g2.setAttribute('normal', new THREE.BufferAttribute(nrm, 3).setUsage(THREE.DynamicDrawUsage));
      const uvA = new Float32Array(N * 2);
      for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) { const k = j * NX + i; uvA[k * 2] = i / (NX - 1); uvA[k * 2 + 1] = 1 - j / (NY - 1); }
      g2.setAttribute('uv', new THREE.BufferAttribute(uvA, 2));
      const idx = [];
      for (let j = 0; j < NY - 1; j++) for (let i = 0; i < NX - 1; i++) { const a = j * NX + i, b = a + 1, c = a + NX, e = c + 1; idx.push(a, c, b, b, c, e); }
      g2.setIndex(idx);
      const dTex = tex(makeDressingTex(w, h, pw, ph, 5));
      const seepU = { uSeep: { value: new THREE.Vector3(0.5, 0.5, 0) }, uPadRect: { value: new THREE.Vector4(pw / w, ph / h, w, h) }, tNoiseD: { value: noiseTex } };
      const dMat = keep(new THREE.MeshPhysicalMaterial({ map: dTex, color: 0xf2efe9, roughness: 0.86, sheen: 0.35, sheenRoughness: 0.7, sheenColor: new THREE.Color(1, 1, 1), side: THREE.DoubleSide }));
      dMat.onBeforeCompile = sh => {
        Object.assign(sh.uniforms, seepU);
        sh.fragmentShader = sh.fragmentShader
          .replace('#include <common>', '#include <common>\nuniform vec3 uSeep; uniform vec4 uPadRect; uniform sampler2D tNoiseD;')
          .replace('#include <map_fragment>', `#include <map_fragment>
            vec2 nzq = (vUv - 0.5) * uPadRect.zw;
            vec2 nzc = (uSeep.xy - 0.5) * uPadRect.zw;
            float nzPad = (1.0 - smoothstep(-0.001, 0.0008, abs(nzq.x) - uPadRect.x * uPadRect.z * 0.5)) * (1.0 - smoothstep(-0.001, 0.0008, abs(nzq.y) - uPadRect.y * uPadRect.w * 0.5));
            float nzn = texture2D(tNoiseD, nzq * 18.0).r;
            float nzr = uSeep.z * 0.012 * (0.75 + 0.5 * nzn);
            float nzd = length((nzq - nzc) * vec2(0.42, 1.0)) * (0.85 + 0.3 * texture2D(tNoiseD, nzq * 7.0 + 0.3).g);
            float nzs = (1.0 - smoothstep(nzr * 0.55, nzr, nzd)) * nzPad * step(0.001, uSeep.z);
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(vec3(0.62, 0.07, 0.05), vec3(0.38, 0.03, 0.02), smoothstep(0.0, nzr, nzr - nzd)), nzs * 0.85);`);
      };
      dMat.customProgramCacheKey = () => 'nza3d-dressing-2';
      const mesh = new THREE.Mesh(g2, dMat);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false;
      scene.add(mesh);

      const D = { state: 'rest', stuck: 0, mesh, size: [w, h], pad: [pw, ph], carriedLift: 0.022, _target: new THREE.Vector3(), _grabbing: false };
      function computeNormals(src, out) {
        for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
          const k = j * NX + i;
          const l = j * NX + Math.max(0, i - 1), r = j * NX + Math.min(NX - 1, i + 1), u = Math.max(0, j - 1) * NX + i, dn = Math.min(NY - 1, j + 1) * NX + i;
          const ax = src[r * 3] - src[l * 3], ay = src[r * 3 + 1] - src[l * 3 + 1], az = src[r * 3 + 2] - src[l * 3 + 2];
          const bx = src[dn * 3] - src[u * 3], by = src[dn * 3 + 1] - src[u * 3 + 1], bz = src[dn * 3 + 2] - src[u * 3 + 2];
          let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
          const L = Math.hypot(nx, ny, nz) || 1;
          nx /= L; ny /= L; nz /= L;
          if (ny < 0 && AXIS === 'none') { nx = -nx; ny = -ny; nz = -nz; }
          out[k * 3] = nx; out[k * 3 + 1] = ny; out[k * 3 + 2] = nz;
        }
      }
      const tmpN = new Float32Array(N * 3);
      function refreshMesh() {
        computeNormals(pos, tmpN);
        // make the normals point away from the skin
        for (let k = 0; k < N; k++) {
          _a.set(pos[k * 3], pos[k * 3 + 1], pos[k * 3 + 2]);
          const q = toSurf(_a); surf(q.s, q.t, P, Nn);
          if (tmpN[k * 3] * Nn.x + tmpN[k * 3 + 1] * Nn.y + tmpN[k * 3 + 2] * Nn.z < 0) { tmpN[k * 3] *= -1; tmpN[k * 3 + 1] *= -1; tmpN[k * 3 + 2] *= -1; }
          const off = padMask[k] * padH;
          rend[k * 3] = pos[k * 3] + tmpN[k * 3] * off; rend[k * 3 + 1] = pos[k * 3 + 1] + tmpN[k * 3 + 1] * off; rend[k * 3 + 2] = pos[k * 3 + 2] + tmpN[k * 3 + 2] * off;
        }
        computeNormals(rend, nrm);
        for (let k = 0; k < N; k++) if (nrm[k * 3] * tmpN[k * 3] + nrm[k * 3 + 1] * tmpN[k * 3 + 1] + nrm[k * 3 + 2] * tmpN[k * 3 + 2] < 0) { nrm[k * 3] *= -1; nrm[k * 3 + 1] *= -1; nrm[k * 3 + 2] *= -1; }
        g2.attributes.position.needsUpdate = true; g2.attributes.normal.needsUpdate = true;
        g2.computeBoundingSphere();
      }
      function nearest(pt) {
        let best = Infinity, bi = 0;
        for (let k = 0; k < N; k++) {
          const dx = pos[k * 3] - pt.x, dy = pos[k * 3 + 1] - pt.y, dz = pos[k * 3 + 2] - pt.z, d = dx * dx + dy * dy + dz * dz;
          if (d < best) { best = d; bi = k; }
        }
        return { k: bi, d: Math.sqrt(best) };
      }
      D.pick = hit => {
        if (!hit) return null;
        const nr = nearest(hit.point);
        if (nr.d > 0.006) return null;
        const i = nr.k % NX, j = Math.floor(nr.k / NX);
        const edgeCells = 2;
        if (i <= edgeCells || j <= edgeCells || i >= NX - 1 - edgeCells || j >= NY - 1 - edgeCells) return 'edge';
        return 'body';
      };
      D.grab = hit => {
        if (D.pick(hit) !== 'edge' || D.stuck > 0.25) return false;
        const nr = nearest(hit.point);
        const gi = nr.k % NX, gj = Math.floor(nr.k / NX);
        const dl = Math.min(gi, NX - 1 - gi), dr = Math.min(gj, NY - 1 - gj);
        pinned.fill(0);
        const alongX = dr < dl;      // grabbed the top or bottom edge
        for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
          const k = j * NX + i;
          const onEdge = alongX ? (Math.abs(j - gj) <= 1 && (gj <= 2 ? j <= 1 : j >= NY - 2)) : (Math.abs(i - gi) <= 1 && (gi <= 2 ? i <= 1 : i >= NX - 2));
          const span = alongX ? Math.abs(i - gi) / NX : Math.abs(j - gj) / NY;
          if (onEdge && span < 0.32) { pinned[k] = 1; stuck[k] = 0; stick[k] = 0; }
        }
        // every vertex keeps its offset from the hand; the far side droops (carryW 0 at the held edge → 1)
        const iE = gi <= 2 ? 0 : NX - 1, jE = gj <= 2 ? 0 : NY - 1;
        for (let k = 0; k < N; k++) {
          pinOff[k * 3] = pos[k * 3] - hit.point.x; pinOff[k * 3 + 1] = pos[k * 3 + 1] - hit.point.y; pinOff[k * 3 + 2] = pos[k * 3 + 2] - hit.point.z;
          const i = k % NX, j = Math.floor(k / NX);
          carryW[k] = alongX ? Math.abs(j - jE) / (NY - 1) : Math.abs(i - iE) / (NX - 1);
          stuck[k] = 0; stick[k] = 0;
        }
        D._target.copy(hit.point);
        D._lift = 0;
        D.state = 'carried';
        return true;
      };
      D.move = hit => { if (D.state === 'carried' && hit) { D._target.copy(hit.point); D._normal = hit.normal.clone(); } };
      D.release = () => { if (D.state === 'carried') { pinned.fill(0); D.state = 'falling'; D._settle = 0; } };
      D.rub = (hit, dt) => {
        if (!hit || D.state === 'carried') return 0;
        const R2 = 0.014;
        let touched = 0;
        for (let k = 0; k < N; k++) {
          const dx = pos[k * 3] - hit.point.x, dy = pos[k * 3 + 1] - hit.point.y, dz = pos[k * 3 + 2] - hit.point.z;
          const dd = Math.hypot(dx, dy, dz);
          if (dd > R2) continue;
          touched++;
          const f = 1 - dd / R2;
          _a.set(pos[k * 3], pos[k * 3 + 1], pos[k * 3 + 2]);
          const q = toSurf(_a);
          const hs = heightAt(q.s, q.t) + thick + stitchClear(q.s, q.t);
          if (q.h - hs < 0.0016) {
            stick[k] = Math.min(1, stick[k] + dt * 4.6 * f);
            if (stick[k] >= 1 && !stuck[k]) {
              stuck[k] = 1;
              surf(q.s, q.t, P, Nn); P.addScaledVector(Nn, hs);
              pos[k * 3] = prev[k * 3] = P.x; pos[k * 3 + 1] = prev[k * 3 + 1] = P.y; pos[k * 3 + 2] = prev[k * 3 + 2] = P.z;
            }
          } else {
            surf(q.s, q.t, P, Nn);
            pos[k * 3] -= Nn.x * 0.0015 * f; pos[k * 3 + 1] -= Nn.y * 0.0015 * f; pos[k * 3 + 2] -= Nn.z * 0.0015 * f;
          }
        }
        if (D.state === 'rest' || D.state === 'falling') D.state = 'placed';
        return touched;
      };
      // fraction of the given skin points that lie under the absorbent pad
      D.covers = uvList => {
        if (!uvList || !uvList.length) return 0;
        let n = 0;
        for (const uv of uvList) {
          const sp = S.surfaceAt(uv);
          const nr = nearest(sp.point);
          if (nr.d < 0.004 && padMask[nr.k] > 0.5) n++;
        }
        return n / uvList.length;
      };
      D.seep = (amount, uv) => {
        seepU.uSeep.value.z = clamp(amount, 0, 1);
        if (uv) { const sp = S.surfaceAt(uv), nr = nearest(sp.point); seepU.uSeep.value.x = uvA[nr.k * 2]; seepU.uSeep.value.y = uvA[nr.k * 2 + 1]; }
      };
      D.center = () => { let x = 0, y = 0, z = 0; for (let k = 0; k < N; k++) { x += pos[k * 3]; y += pos[k * 3 + 1]; z += pos[k * 3 + 2]; } return new THREE.Vector3(x / N, y / N, z / N); };
      D.remove = () => { scene.remove(mesh); const i = dressings.indexOf(D); if (i >= 0) dressings.splice(i, 1); };
      D.step = dt => {
        if (D.state === 'rest') return;   // lying on the tray / beside the wound until picked up
        const sub = 3, h2 = Math.min(dt, 0.04) / sub;
        const gy = -9.8;
        const lift = D.state === 'carried' ? (D._lift = lerp(D._lift || 0, D.carriedLift, 1 - Math.exp(-dt * 10))) : 0;
        const tn = D._normal || _n.set(0, 1, 0);
        for (let it = 0; it < sub; it++) {
          for (let k = 0; k < N; k++) {
            const i3 = k * 3;
            if (stuck[k]) continue;
            if (pinned[k]) {
              const tx = D._target.x + tn.x * lift + pinOff[i3], ty = D._target.y + tn.y * lift + pinOff[i3 + 1], tz = D._target.z + tn.z * lift + pinOff[i3 + 2];
              prev[i3] = pos[i3]; prev[i3 + 1] = pos[i3 + 1]; prev[i3 + 2] = pos[i3 + 2];
              pos[i3] = lerp(pos[i3], tx, 0.5); pos[i3 + 1] = lerp(pos[i3 + 1], ty, 0.5); pos[i3 + 2] = lerp(pos[i3 + 2], tz, 0.5);
              continue;
            }
            const damp = contact[k] ? 0.55 : D.state === 'carried' ? 0.86 : 0.985;
            const vx = (pos[i3] - prev[i3]) * damp, vy = (pos[i3 + 1] - prev[i3 + 1]) * damp, vz = (pos[i3 + 2] - prev[i3 + 2]) * damp;
            prev[i3] = pos[i3]; prev[i3 + 1] = pos[i3 + 1]; prev[i3 + 2] = pos[i3 + 2];
            pos[i3] += vx; pos[i3 + 1] += vy + gy * h2 * h2 * 0.35; pos[i3 + 2] += vz;
          }
          for (let rep = 0; rep < 5; rep++) {
            for (let c = 0; c < consArr.length; c += 4) {
              const a = consArr[c], b = consArr[c + 1], rest = consArr[c + 2], kf = consArr[c + 3];
              const fa = stuck[a] || pinned[a], fb = stuck[b] || pinned[b];
              if (fa && fb) continue;
              const a3 = a * 3, b3 = b * 3;
              const dx = pos[b3] - pos[a3], dy = pos[b3 + 1] - pos[a3 + 1], dz = pos[b3 + 2] - pos[a3 + 2];
              const dd = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1e-9;
              let diff = ((dd - rest) / dd) * kf;
              if (dd < rest) diff *= 0.35;   // cloth resists stretching more than compression
              const wa = fa ? 0 : fb ? 1 : 0.5, wb = fb ? 0 : fa ? 1 : 0.5;
              pos[a3] += dx * diff * wa; pos[a3 + 1] += dy * diff * wa; pos[a3 + 2] += dz * diff * wa;
              pos[b3] -= dx * diff * wb; pos[b3 + 1] -= dy * diff * wb; pos[b3 + 2] -= dz * diff * wb;
            }
          }
          // carried: the free part follows the hand loosely, sagging toward the skin
          if (D.state === 'carried') {
            for (let k = 0; k < N; k++) {
              if (pinned[k]) continue;
              const i3 = k * 3, cw = carryW[k], up = lift * (1 - 0.72 * cw);
              const tx = D._target.x + tn.x * up + pinOff[i3], ty = D._target.y + tn.y * up + pinOff[i3 + 1], tz = D._target.z + tn.z * up + pinOff[i3 + 2];
              const kk = 0.38 * (1 - 0.4 * cw);
              pos[i3] += (tx - pos[i3]) * kk; pos[i3 + 1] += (ty - pos[i3 + 1]) * kk; pos[i3 + 2] += (tz - pos[i3 + 2]) * kk;
            }
          }
          // collide with the skin
          let moving = 0;
          for (let k = 0; k < N; k++) {
            if (stuck[k]) { contact[k] = 1; continue; }
            const i3 = k * 3;
            _a.set(pos[i3], pos[i3 + 1], pos[i3 + 2]);
            const q = toSurf(_a);
            const hs = heightAt(q.s, q.t) + thick + padMask[k] * 0.0002 + stitchClear(q.s, q.t);
            if (q.h < hs) {
              surf(q.s, q.t, P, Nn); P.addScaledVector(Nn, hs);
              pos[i3] = P.x; pos[i3 + 1] = P.y; pos[i3 + 2] = P.z;
              prev[i3] = lerp(prev[i3], pos[i3], 0.7); prev[i3 + 1] = lerp(prev[i3 + 1], pos[i3 + 1], 0.7); prev[i3 + 2] = lerp(prev[i3 + 2], pos[i3 + 2], 0.7);
              contact[k] = 1;
            } else contact[k] = q.h - hs < 0.0008 ? 1 : 0;
            moving += Math.abs(pos[i3 + 1] - prev[i3 + 1]);
          }
          if (D.state === 'falling') { D._settle = moving < 0.00002 * N ? (D._settle || 0) + h2 : 0; if (D._settle > 0.35) D.state = 'placed'; }
        }
        let s = 0, ws = 0;
        for (let k = 0; k < N; k++) { s += stick[k] * wgt[k]; ws += wgt[k]; }
        D.stuck = s / ws;
        refreshMesh();
      };
      refreshMesh();
      dressings.push(D);
      return D;
    }
    S.dressing = { create: createDressing, get list() { return dressings.slice(); } };

    // compile every shader a scene will need up front (tools, dressing) so the first use of a
    // tool does not hitch. Call once after setup, ideally behind a loading veil.
    S.prewarm = (names, withDressing = true) => {
      const list = names || Object.keys(BUILD);
      const shown = [];
      for (const n of list) {
        const t = tools.get(n);
        if (t && !t.group.visible) { t.group.visible = true; t.group.position.set(0, -5, 0); shown.push(t); }
      }
      const D = withDressing ? createDressing({ uv: [0.02, 0.02], size: [0.02, 0.02], pad: [0.01, 0.01] }) : null;
      // one of every marker kind and a stitch (their materials are created lazily)
      const kinds = ['ring', 'dashed', 'check', 'cross', 'dot', 'pin'];
      kinds.forEach(k => markers.set(`__warm_${k}`, { uv: [0.03, 0.03], kind: k }));
      const st = stitches.add({ a: [0.03, 0.03], b: [0.04, 0.03] });
      try { renderer.compile(scene, camera); } catch (e) { console.error('[NZA3D] prewarm', e); }
      shown.forEach(t => { if (tools.active !== t) t.group.visible = false; });
      if (D) D.remove();
      kinds.forEach(k => markers.remove(`__warm_${k}`));
      st.remove();
    };

    /* ═════════════ DRAPE ═════════════ */
    if (o.drape) {
      const dp = o.drape === true ? {} : o.drape;
      const r0 = dp.radius || 0.05;
      const c = uvToST(dp.uv || (o.focus && o.focus.uv) || [0.5, 0.5]);
      const smax = W * 0.78, tmax = H * 0.78;
      const AS = 180, RS = 46;
      const pos = new Float32Array((AS + 1) * (RS + 1) * 3), uvs = new Float32Array((AS + 1) * (RS + 1) * 2);
      const R3 = rng(seed + 7);
      const folds = Array.from({ length: 9 }, () => ({ a: R3() * Math.PI, f: 30 + R3() * 70, p: R3() * 6, amp: 0.0012 + R3() * 0.0035 }));
      for (let a = 0; a <= AS; a++) {
        const th = (a / AS) * TAU, cs = Math.cos(th), sn = Math.sin(th);
        const rmax = Math.min(Math.abs(cs) > 1e-4 ? (smax - Math.sign(cs) * c[0]) / Math.abs(cs) : 9, Math.abs(sn) > 1e-4 ? (tmax - Math.sign(sn) * c[1]) / Math.abs(sn) : 9);
        for (let k = 0; k <= RS; k++) {
          const f = Math.pow(k / RS, 1.7), rr = r0 + (Math.max(rmax, r0 + 0.01) - r0) * f;
          const s = c[0] + cs * rr, t = c[1] + sn * rr;
          surf(s, t, _p, _n);
          const away = smooth(r0, r0 + 0.035, rr);
          let z = 0.0014 + away * 0.0012;
          for (const fo of folds) z += Math.max(0, Math.sin((s * Math.cos(fo.a) + t * Math.sin(fo.a)) * fo.f + fo.p)) * fo.amp * away;
          z += (noiseAt(0, s * 6 + 1, t * 6) - 0.5) * 0.004 * away;
          _p.addScaledVector(_n, z);
          const i = a * (RS + 1) + k;
          pos[i * 3] = _p.x; pos[i * 3 + 1] = _p.y; pos[i * 3 + 2] = _p.z;
          uvs[i * 2] = s * 9; uvs[i * 2 + 1] = t * 9;
        }
      }
      const idx = [];
      for (let a = 0; a < AS; a++) for (let k = 0; k < RS; k++) { const i0 = a * (RS + 1) + k, i1 = i0 + RS + 1; idx.push(i0, i0 + 1, i1, i1, i0 + 1, i1 + 1); }
      const dg = geo(new THREE.BufferGeometry());
      dg.setAttribute('position', new THREE.BufferAttribute(pos, 3)); dg.setAttribute('uv', new THREE.BufferAttribute(uvs, 2)); dg.setIndex(idx);
      dg.computeVertexNormals();
      const weave = makeWeave({ threads: 22, seed: 4, fuzz: 0.4 });
      const wn = tex(weave.normal, false), wa = tex(weave.albedo);
      for (const t of [wn, wa]) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(16, 16); t.anisotropy = 8; }
      const drape = new THREE.Mesh(dg, keep(new THREE.MeshPhysicalMaterial({
        color: new THREE.Color(dp.color !== undefined ? dp.color : 0x2c7e8a), map: wa, normalMap: wn, normalScale: new THREE.Vector2(0.7, 0.7),
        roughness: 0.94, sheen: 0.7, sheenRoughness: 0.8, sheenColor: new THREE.Color(0x9fe6e0), side: THREE.DoubleSide,
      })));
      drape.castShadow = true; drape.receiveShadow = true;
      scene.add(drape);
      // clear adhesive film ring at the window edge
      const ringPts = [];
      const film = new THREE.Mesh(geo(new THREE.RingGeometry(r0 - 0.003, r0 + 0.004, 96, 1)), keep(new THREE.MeshPhysicalMaterial({ color: 0xffffff, transparent: true, opacity: 0.12, roughness: 0.05, clearcoat: 1, depthWrite: false })));
      const fp = film.geometry.attributes.position;
      for (let i = 0; i < fp.count; i++) {
        const s = c[0] + fp.getX(i), t = c[1] - fp.getY(i);
        surf(s, t, _p, _n); _p.addScaledVector(_n, heightAt(s, t) + 0.0003);
        fp.setXYZ(i, _p.x, _p.y, _p.z);
        ringPts.push(_p.clone());
      }
      film.geometry.computeVertexNormals();
      film.renderOrder = 4;
      scene.add(film);
      S.drape = { mesh: drape, radius: r0, uv: stToUv(c[0], c[1]) };
    }

    /* ═════════════ LOOP ═════════════ */
    let lastW = 0, lastH = 0, raf = 0, running = false, lastT = 0;
    function effectiveZoom(el) {
      let z = 1;
      for (let n = el; n && n.nodeType === 1; n = n.parentElement) { const v = parseFloat(getComputedStyle(n).zoom); if (v > 0) z *= v; }
      return z;
    }
    function resize() {
      let w, h;
      if (o.fullscreen) { w = window.innerWidth; h = window.innerHeight; }
      else { w = container.clientWidth; h = container.clientHeight; }
      w = Math.max(2, Math.floor(w)); h = Math.max(2, Math.floor(h));
      if (w === lastW && h === lastH) return;
      lastW = w; lastH = h;
      renderer.setSize(w, h, false);
      if (o.fullscreen) { const z = effectiveZoom(container); cv.style.width = `${w / z}px`; cv.style.height = `${h / z}px`; }
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      pMat.uniforms.uScale.value = h / (2 * Math.tan((camera.fov * Math.PI) / 360));
      emit('resize', w, h);
    }
    S.resize = () => { lastW = 0; resize(); };
    function placeLights() {
      const hm = ctl.home;
      surf(hm.s, hm.t, _p, _n);
      tangents(hm.s, hm.t, _a, _b);
      key.position.copy(_p).addScaledVector(_n, 0.82).addScaledVector(_a, 0.16).addScaledVector(_b, -0.22);
      key.target.position.copy(_p);
      keyB.position.copy(_p).addScaledVector(_n, 0.82).addScaledVector(_a, 0.02).addScaledVector(_b, -0.12);
      keyB.target.position.copy(_p);
      key2.position.copy(_p).addScaledVector(_n, 0.8).addScaledVector(_a, -0.12).addScaledVector(_b, -0.3);
      key2.target.position.copy(_p);
      fill.position.copy(_p).addScaledVector(_n, 0.6).addScaledVector(_a, -0.42).addScaledVector(_b, 0.3);
      fill.target.position.copy(_p);
      key.target.updateMatrixWorld(); keyB.target.updateMatrixWorld(); key2.target.updateMatrixWorld(); fill.target.updateMatrixWorld();
    }
    function step(dt, render = true) {
      S.time += dt;
      resize();
      applyCamera(dt);
      placeLights();
      updateTools(dt);
      updateFluids(dt);
      for (let i = 0; i < dressings.length; i++) dressings[i].step(dt);
      emit('frame', dt);
      applyDecays(dt);
      flushBrushes();
      if (fieldDirty) renderField();
      updateMarkers(S.time);
      keyDir.copy(key.position).sub(key.target.position).normalize().transformDirection(camera.matrixWorldInverse);
      U.uKeyDir.value.copy(keyDir);
      if (!render) return;
      renderer.setRenderTarget(null);
      renderer.render(scene, camera);
    }
    function frame(now) {
      if (!running) return;
      raf = requestAnimationFrame(frame);
      const dt = clamp((now - lastT) / 1000, 0, 0.05);
      lastT = now;
      try { step(dt); } catch (e) { console.error('[NZA3D] frame', e); }
    }
    S.start = () => { if (running || S.disposed) return; running = true; lastT = performance.now(); raf = requestAnimationFrame(frame); };
    S.stop = () => { running = false; cancelAnimationFrame(raf); };
    S.step = (dt, render = true) => step(dt || 1 / 60, render);
    S.running = () => running;

    S.dispose = () => {
      if (S.disposed) return;
      S.stop();
      cv.removeEventListener('pointerdown', onDown);
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      cv.removeEventListener('wheel', onWheel);
      cv.removeEventListener('contextmenu', onCtx);
      window.removeEventListener('keydown', onKey);
      scene.traverse(ob => {
        if (ob.geometry) bin.add(ob.geometry);
        if (ob.material) (Array.isArray(ob.material) ? ob.material : [ob.material]).forEach(m => { bin.add(m); for (const k in m) { const v = m[k]; if (v && v.isTexture && v !== scene.environment) bin.add(v); } });
      });
      bin.forEach(x => { try { x.dispose(); } catch (e) { /* already gone */ } });
      bin.clear();
      try { key.dispose(); keyB.dispose(); key2.dispose(); fill.dispose(); } catch (e) { /* r149 lights */ }
      renderer.renderLists.dispose();
      for (const k in handlers) delete handlers[k];
      if (vig && vig.parentNode) vig.parentNode.removeChild(vig);
      releaseRenderer(entry);
      S.disposed = true;
    };

    // first frame setup
    resize();
    controls.frame((o.focus && o.focus.uv) || [0.5, 0.5], (o.focus && o.focus.view) || Math.min(W, 0.16));
    applyCamera(1);
    placeLights();
    return S;
  }

  /* ═════════════════════════════ GLSL ═════════════════════════════ */

  // Wound field: R inside (tissue), G height (mm), B rim / erythema, A burn severity
  const FIELD_FRAG = `
    precision highp float;
    uniform sampler2D tData;
    uniform sampler2D tNoise;
    uniform vec2 uPatch;
    uniform vec4 uWR;
    uniform int uWounds;
    uniform int uBumps;
    uniform float uEnc;
    varying vec2 vUv;
    float cross2(vec2 a, vec2 b) { return a.x * b.y - a.y * b.x; }
    void main() {
      vec2 uvP = uWR.xy + vUv * uWR.zw;
      vec2 P = vec2((uvP.x - 0.5) * uPatch.x, (0.5 - uvP.y) * uPatch.y) * 1000.0;
      float inside = 0.0, height = 0.0, rim = 0.0, burn = 0.0;
      for (int w = 0; w < 8; w++) {
        if (w >= uWounds) break;
        vec4 bb = texelFetch(tData, ivec2(3, w), 0);
        if (P.x < bb.x || P.y < bb.y || P.x > bb.z || P.y > bb.w) continue;
        vec4 h0 = texelFetch(tData, ivec2(0, w), 0);
        vec4 h1 = texelFetch(tData, ivec2(1, w), 0);
        vec4 h2 = texelFetch(tData, ivec2(2, w), 0);
        vec4 h4 = texelFetch(tData, ivec2(4, w), 0);
        int type = int(h0.x + 0.5);
        float depth = h0.w, cut = h1.x, open = h1.y, rimW = max(h1.z, 0.05), rimS = h1.w;
        float jag = h2.x, seed = h2.y, taperE = max(h2.z, 0.05), swell = h2.w;
        if (type == 1) {
          int n = int(h0.y + 0.5);
          float gape = h0.z;
          float total = max(h4.x, 0.001);
          float best = 1e9, bestL = 0.0, bestSide = 1.0, bestC = 0.0, bestG = 1.0, acc = 0.0;
          vec4 a = texelFetch(tData, ivec2(8, w), 0);
          for (int i = 1; i < 48; i++) {
            if (i >= n) break;
            vec4 b = texelFetch(tData, ivec2(8 + i, w), 0);
            vec2 ab = b.xy - a.xy;
            float len = length(ab);
            float tt = clamp(dot(P - a.xy, ab) / max(len * len, 1e-6), 0.0, 1.0);
            float d = length(P - (a.xy + ab * tt));
            if (d < best) { best = d; bestL = acc + tt * len; bestSide = cross2(ab, P - a.xy) >= 0.0 ? 1.0 : -1.0; bestC = mix(a.z, b.z, tt); bestG = mix(a.w, b.w, tt); }
            acc += len;
            a = b;
          }
          float tN = bestL / total;
          float cutE = max(cut, 1e-4);
          float exists = step(0.0005, cut) * (1.0 - step(cutE + 0.0001, tN));
          float env = exists * pow(max(sin(3.14159265 * clamp(tN / cutE, 0.0, 1.0)), 0.0), taperE);
          float jn = texture2D(tNoise, vec2(bestL * 0.043 + seed, bestSide * 0.31 + seed * 0.7)).r - 0.5;
          float jn2 = texture2D(tNoise, vec2(bestL * 0.11 + seed * 1.3, bestSide * 0.17 + seed)).g - 0.5;
          float g = gape * open * env * (1.0 - bestC) * bestG;
          float halfG = max(0.5 * g * (1.0 + jag * (jn * 0.95 + jn2 * 0.22)), 0.0);
          float ins = halfG > 0.03 ? 1.0 - smoothstep(halfG - 0.07, halfG + 0.07, best) : 0.0;
          float x = clamp(best / max(halfG, 0.03), 0.0, 1.0);
          float dep = depth * pow(env, 0.4) * (1.0 - 0.96 * bestC) * mix(0.35, 1.0, open);
          height += ins * -dep * (1.0 - pow(x, 2.4));
          float ed = max(best - halfG, 0.0);
          float near = exp(-pow(ed / rimW, 2.0));
          height += (1.0 - ins) * (swell * near * sqrt(env + 0.0001) * exists - 0.12 * dep * exp(-pow(ed / 0.3, 2.0)));
          float seam = exists * bestC * smoothstep(0.0, 0.25, env) * (1.0 - smoothstep(0.06, 0.3, best));
          height += exists * bestC * 0.28 * exp(-pow(best / 1.4, 2.0)) * sqrt(env + 0.0001);
          inside = max(inside, max(ins, seam * 0.7));
          float rimN = 0.75 + 0.5 * texture2D(tNoise, P * 0.11 + seed).g;
          rim = max(rim, rimS * rimN * exp(-pow(ed / rimW, 1.5)) * exists * smoothstep(0.0, 0.2, env + 0.06));
        } else if (type == 2) {
          vec2 dv = P - h4.xy;
          float d = length(dv);
          float ang = atan(dv.y, dv.x);
          float irr = 1.0 + jag * (texture2D(tNoise, vec2(cos(ang), sin(ang)) * 0.23 + seed).r - 0.5) * 0.7;
          float r = h4.z * irr * max(open, 0.05);
          float ins = 1.0 - smoothstep(r - 0.08, r + 0.08, d);
          float x = clamp(d / max(r, 0.05), 0.0, 1.0);
          height += ins * (-depth * pow(1.0 - x, 1.8) - 0.5 * (1.0 - x * x));
          float ed = max(d - r, 0.0);
          height += (1.0 - ins) * swell * exp(-pow(ed / (h4.w * 1.6 + 0.1), 2.0));
          inside = max(inside, ins);
          rim = max(rim, rimS * (1.0 - smoothstep(h4.w * 0.6, h4.w * 1.5, ed)) * (0.75 + 0.5 * texture2D(tNoise, P * 0.08 + seed).g));
        } else if (type == 3) {
          vec4 h5 = texelFetch(tData, ivec2(5, w), 0);
          vec2 q = (P - h4.xy) / max(h4.zw, vec2(0.1));
          float d = length(q);
          float ang = atan(q.y, q.x);
          float nA = texture2D(tNoise, vec2(cos(ang), sin(ang)) * 0.19 + seed).r;
          float nB = texture2D(tNoise, P * 0.035 + seed * 0.7).g;
          float dn = d / max(0.2, 1.0 + h5.x * ((nA - 0.5) * 1.3 + (nB - 0.5) * 0.6));
          float core = 1.0 - smoothstep(0.9, 1.0, dn);
          float marg = 1.0 - smoothstep(1.0, 1.42, dn);
          float deg = h5.y;
          float inner = clamp((1.0 - dn) * 1.6 + (nB - 0.5) * 0.5, 0.0, 1.0);
          float sev = deg < 1.5 ? 0.3 : (deg < 2.5 ? mix(0.4, 0.62, inner) : mix(0.55, 1.0, smoothstep(0.1, 0.6, inner)));
          burn = max(burn, core * sev * open);
          rim = max(rim, marg * (1.0 - core * 0.6) * (deg >= 1.5 ? 0.9 : 0.6) * open);
          height += core * open * (deg >= 2.5 ? -0.35 * smoothstep(0.6, 0.9, sev) : 0.08);
        }
      }
      for (int i = 0; i < 256; i++) {
        if (i >= uBumps) break;
        vec4 b = texelFetch(tData, ivec2(i - (i / 64) * 64, 8 + i / 64), 0);
        vec2 dv = P - b.xy;
        float d2 = dot(dv, dv), r2 = b.z * b.z;
        if (d2 < r2) { float f = 1.0 - d2 / r2; height += b.w * f * f; }
      }
      float hOut = uEnc > 0.5 ? clamp((height + 16.0) / 32.0, 0.0, 1.0) : height;
      gl_FragColor = vec4(clamp(inside, 0.0, 1.0), hOut, clamp(rim, 0.0, 1.0), clamp(burn, 0.0, 1.0));
    }`;

  const BRUSH_VERT = `
    attribute vec2 iCenter;
    attribute vec2 iRadius;
    attribute vec4 iMask;
    attribute vec4 iParams;
    attribute vec2 iExtra;
    uniform vec2 uPatch;
    varying vec2 vLocal;
    varying vec2 vWorld;
    varying vec4 vMask;
    varying vec4 vParams;
    varying vec2 vExtra;
    void main() {
      vec2 p = position.xy;
      float c = cos(iParams.w), s = sin(iParams.w);
      vec2 off = vec2(c * p.x * iRadius.x - s * p.y * iRadius.y, s * p.x * iRadius.x + c * p.y * iRadius.y);
      vec2 uv = iCenter + off / uPatch;
      vLocal = p; vWorld = uv * uPatch; vMask = iMask; vParams = iParams; vExtra = iExtra;
      gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    }`;
  const BRUSH_FRAG = `
    uniform sampler2D tNoise;
    varying vec2 vLocal;
    varying vec2 vWorld;
    varying vec4 vMask;
    varying vec4 vParams;
    varying vec2 vExtra;
    void main() {
      float f = 1.0;
      if (vParams.x < 1.5) {
        float r = length(vLocal);
        if (r >= 1.0) discard;
        f = 1.0 - smoothstep(vParams.x, 1.0, r);
      }
      if (vParams.y > 0.0) {
        float n = texture2D(tNoise, vWorld * vParams.z + vec2(vExtra.y, vExtra.y * 0.61)).r;
        f *= mix(1.0, smoothstep(0.3, 0.7, n) * 1.5, vParams.y);
      }
      gl_FragColor = vMask * clamp(f * vExtra.x, 0.0, 1.0);
    }`;

  const SKIN_PARS = `
    uniform sampler2D tField;
    uniform sampler2D tMaskA;
    uniform sampler2D tMaskB;
    uniform sampler2D tNoise;
    uniform sampler2D tMicro2;
    uniform vec2 uPatch;
    uniform vec2 uFieldTexel;
    uniform vec2 uLayerTexel;
    uniform float uFieldEnc;
    uniform vec4 uWR;
    uniform vec2 uWork;
    float nzaWin;
    vec2 nzaW;
    uniform float uMicroRep;
    uniform float uHair;
    uniform vec3 uHairColor;
    uniform vec3 uKeyDir;
    uniform vec3 uKeyColor;
    uniform float uMicroNormal;
    uniform float uSkinRough;
    uniform float uFieldNormal;
    uniform float uSSS;
    uniform float uDark;
    uniform float uSebum;
    uniform float uInsideLod;
    float nzaInside; float nzaDepthN; float nzaWet; float nzaSmooth; float nzaThick; float nzaThin; float nzaGrit; float nzaGr; float nzaCl; float nzaCav;
    vec2 nzaUv1; vec2 nzaUv2; vec2 nzaP;
    vec4 nzaM1; vec4 nzaM2; vec4 nzaN3; vec4 nzaN4;
    vec2 nzaRot(vec2 v, float a) { float c = cos(a), s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }
    float nzaFieldH(vec2 w) { float h = texture2D(tField, w).g; return (uFieldEnc > 0.5 ? h * 32.0 - 16.0 : h) * nzaWin; }
    // fluid film thickness (mm): wet blood ≈ 0.35 mm, clot ≈ 0.7 mm
    float nzaFilm(vec2 w) { return texture2D(tMaskA, w).r * 0.35 + texture2D(tMaskB, w).b * 0.7; }
  `;
  const SKIN_MAP = `
    nzaP = vec2((vUv.x - 0.5) * uPatch.x, (0.5 - vUv.y) * uPatch.y);
    nzaW = (vUv - uWR.xy) / uWR.zw;
    nzaWin = smoothstep(0.0, 0.015, nzaW.x) * smoothstep(0.0, 0.015, 1.0 - nzaW.x) * smoothstep(0.0, 0.015, nzaW.y) * smoothstep(0.0, 0.015, 1.0 - nzaW.y);
    vec4 nzaF = texture2D(tField, nzaW);
    float nzaH0 = (uFieldEnc > 0.5 ? nzaF.g * 32.0 - 16.0 : nzaF.g) * nzaWin;
    nzaF.rba *= nzaWin;
    vec4 nzaA = texture2D(tMaskA, nzaW) * nzaWin;
    vec4 nzaB = texture2D(tMaskB, nzaW) * nzaWin;
    // In the groove the walls are steep: the patch uv barely changes across them, so paint would smear
    // into streaks down the walls. Blood, clot and dirt pool in there anyway → read a blurred mip level.
    if (nzaF.r > 0.02) {
      float nzaIb = smoothstep(0.02, 0.5, nzaF.r);
      nzaA = mix(nzaA, textureLod(tMaskA, nzaW, uInsideLod) * nzaWin, nzaIb);
      nzaB = mix(nzaB, textureLod(tMaskB, nzaW, uInsideLod) * nzaWin, nzaIb);
    }
    vec2 nzaQ = vec2(nzaP.x, -nzaP.y);
    nzaUv1 = nzaQ * uMicroRep;
    nzaUv2 = nzaRot(nzaQ * uMicroRep * 0.731, 0.61) + vec2(0.37, 0.19);
    nzaM1 = texture2D(tMicro2, nzaUv1);
    nzaM2 = texture2D(tMicro2, nzaUv2);
    vec4 nzaN1 = texture2D(tNoise, nzaP * 2.3);
    vec4 nzaN2 = texture2D(tNoise, nzaP * 11.0 + 0.5);
    nzaN3 = texture2D(tNoise, nzaP * 37.0 + 0.27);
    nzaN4 = texture2D(tNoise, nzaP * 95.0 + 0.61);
    vec3 nzaCol = texture2D(map, vUv).rgb;
    // micro cavities (furrows, pores) are a touch darker and redder
    nzaCav = 0.5 * (nzaM1.r + nzaM2.r);
    nzaCol *= mix(vec3(1.0), vec3(0.95, 0.9, 0.89), nzaCav);
    // body hair: density varies in patches; a second rotated layer breaks the tiling
    float nzaDen = smoothstep(0.32, 0.68, nzaN1.g);
    float nzaHair = max(nzaM1.g * nzaDen, nzaM2.g * (1.0 - nzaDen) * 0.8);
    nzaCol = mix(nzaCol, uHairColor, clamp(nzaHair, 0.0, 1.0) * clamp(uHair * 1.6, 0.0, 0.9));
    // bruise: red-purple core, yellow-green fringe
    float nzaBr = nzaB.r * (0.7 + 0.6 * nzaN2.g);
    vec3 nzaBc = mix(vec3(0.96, 0.84, 0.66), vec3(0.72, 0.48, 0.58), smoothstep(0.12, 0.45, nzaBr));
    nzaBc = mix(nzaBc, vec3(0.44, 0.3, 0.48), smoothstep(0.45, 0.9, nzaBr));
    nzaCol *= mix(vec3(1.0), nzaBc, smoothstep(0.0, 0.4, nzaBr));
    // wound margin: erythema and a thin abraded epidermis edge
    float nzaRim = clamp(nzaF.b, 0.0, 1.0);
    nzaCol = mix(nzaCol, nzaCol * vec3(0.98, 0.6, 0.52), nzaRim * 0.8);
    nzaCol = mix(nzaCol, vec3(0.5, 0.13, 0.09), smoothstep(0.55, 1.0, nzaRim * (0.6 + 0.8 * nzaN3.r)) * 0.55);
    // iodine
    float nzaIo = nzaA.b * (0.85 + 0.3 * nzaN2.r);
    nzaCol = mix(nzaCol, nzaCol * vec3(0.8, 0.38, 0.08), smoothstep(0.0, 0.7, nzaIo));
    // burns: superficial red → partial (wet pink, sloughed white epidermis) → full thickness (leathery)
    float nzaBs = nzaF.a;
    vec3 nzaEry = nzaCol * vec3(1.0, 0.5, 0.44);
    vec3 nzaPart = mix(vec3(0.82, 0.30, 0.26), vec3(0.93, 0.84, 0.76), smoothstep(0.52, 0.72, nzaN2.b));
    vec3 nzaFull = mix(vec3(0.80, 0.72, 0.56), vec3(0.42, 0.28, 0.16), nzaN2.r);
    nzaCol = mix(nzaCol, nzaEry, smoothstep(0.0, 0.3, nzaBs));
    nzaCol = mix(nzaCol, nzaPart, smoothstep(0.34, 0.5, nzaBs));
    nzaCol = mix(nzaCol, nzaFull, smoothstep(0.66, 0.86, nzaBs));
    float nzaEs = nzaB.a * (0.7 + 0.6 * nzaN3.g);
    nzaCol = mix(nzaCol, mix(vec3(0.22, 0.13, 0.07), vec3(0.05, 0.035, 0.025), smoothstep(0.4, 0.9, nzaEs)), smoothstep(0.08, 0.5, nzaEs));
    // tissue inside the wound: pale dermis lip → raw red → yellow fat lobules → dark depth
    nzaInside = clamp(nzaF.r, 0.0, 1.0);
    nzaDepthN = clamp(-nzaH0 / 6.0, 0.0, 1.0);
    float nzaLob = texture2D(tNoise, nzaP * 71.0 + vec2(0.13, 0.57)).b;
    float nzaFatBand = smoothstep(0.14, 0.3, nzaDepthN) * (1.0 - smoothstep(0.5, 0.8, nzaDepthN)) * smoothstep(0.35, 0.6, texture2D(tNoise, nzaP * 9.0).g);
    float nzaFat = (1.0 - smoothstep(0.28, 0.5, nzaLob)) * nzaFatBand;
    vec3 nzaTis = mix(vec3(0.9, 0.52, 0.44), vec3(0.74, 0.15, 0.09), smoothstep(0.04, 0.26, nzaDepthN));
    nzaTis = mix(nzaTis, mix(vec3(0.98, 0.8, 0.46), vec3(0.92, 0.64, 0.32), nzaN3.g), nzaFat * 0.8);
    nzaTis = mix(nzaTis, vec3(0.44, 0.05, 0.035), smoothstep(0.5, 1.0, nzaDepthN));
    nzaTis *= 0.82 + 0.36 * texture2D(tNoise, nzaP * 52.0 + vec2(nzaH0 * 0.05, 0.0)).g;
    nzaCol = mix(nzaCol, nzaTis, nzaInside);
    // raised skin (lidocaine wheal, blister dome) is pale and slightly translucent
    float nzaWh = smoothstep(0.3, 1.1, nzaH0) * (1.0 - nzaInside) * (1.0 - smoothstep(0.2, 0.6, nzaBs));
    nzaCol = mix(nzaCol, nzaCol * vec3(1.06, 1.07, 1.05) + vec3(0.035, 0.03, 0.03), nzaWh * 0.75);
    // soot / powder stippling
    float nzaSo = nzaA.a;
    nzaCol = mix(nzaCol, nzaCol * 0.22, smoothstep(0.0, 0.7, nzaSo) * 0.75);
    nzaCol = mix(nzaCol, vec3(0.02), step(1.0 - nzaSo * 0.5, nzaN4.a) * 0.9);
    // clotted blood: dark maroon, thick
    nzaCl = nzaB.b * (0.8 + 0.4 * nzaN2.r);
    float nzaClf = smoothstep(0.08, 0.36, nzaCl);
    nzaCol = mix(nzaCol, mix(vec3(0.42, 0.11, 0.065), vec3(0.09, 0.013, 0.009), smoothstep(0.26, 0.9, nzaCl)), nzaClf);
    // wet blood: thin film tints, pools go deep red
    float nzaBl = nzaA.r + (nzaN2.r - 0.5) * 0.06;
    // in the groove blood runs off the walls and pools at the bottom
    nzaBl *= mix(1.0, mix(0.45, 1.15, smoothstep(0.22, 0.72, nzaDepthN)), nzaInside);
    nzaThin = smoothstep(0.03, 0.22, nzaBl);
    nzaThick = smoothstep(0.24, 0.78, nzaBl);
    nzaCol = mix(nzaCol, nzaCol * vec3(0.66, 0.1, 0.075), nzaThin * 0.92);
    nzaCol = mix(nzaCol, vec3(0.2, 0.012, 0.01), nzaThick * 0.96);
    // grime (drawn over the blood: dirt sits in the wound): brown-grey smudges with soft broken edges ...
    nzaGr = nzaA.g;
    float nzaGn = texture2D(tNoise, nzaP * 8.0 + 0.13).r * 0.55 + texture2D(tNoise, nzaP * 29.0 + 0.3).g * 0.45;
    float nzaGf = smoothstep(0.04, 0.5, nzaGr * (0.35 + 0.9 * nzaGn) * (0.45 + 1.1 * nzaN4.r));
    vec3 nzaDirt = mix(vec3(0.52, 0.47, 0.4), vec3(0.27, 0.24, 0.2), nzaGn);
    vec3 nzaDirtCol = mix(nzaCol * nzaDirt, nzaDirt * vec3(0.34, 0.3, 0.26), max(nzaThin, nzaInside) * 0.75);
    nzaCol = mix(nzaCol, nzaDirtCol, nzaGf * 0.92);
    // ... and grit: sparse sand / road-dirt particles where the grime is heavy (one random value per worley cell)
    vec2 nzaGc1 = nzaP * 41.0 + vec2(0.41, 0.17);
    vec2 nzaGc2 = nzaP * 97.0 + vec2(0.71, 0.29);
    float nzaR1 = textureLod(tNoise, (floor(nzaGc1 * 8.0) + 0.5) / 8.0 + vec2(0.0019), 0.0).a;
    float nzaR2 = textureLod(tNoise, (floor(nzaGc2 * 8.0) + 0.5) / 8.0 + vec2(0.0023), 0.0).a;
    float nzaS1 = texture2D(tNoise, nzaGc1).b / (0.6 + 0.8 * nzaR1);
    float nzaS2 = texture2D(tNoise, nzaGc2).b / (0.6 + 0.8 * nzaR2);
    float nzaG1 = (1.0 - smoothstep(0.08, 0.13, nzaS1)) * step(1.0 - clamp(nzaGr - 0.25, 0.0, 1.0) * 0.8, nzaR1);
    float nzaG2 = (1.0 - smoothstep(0.1, 0.16, nzaS2)) * step(1.0 - clamp(nzaGr - 0.15, 0.0, 1.0) * 0.7, nzaR2);
    nzaGrit = clamp(max(nzaG1, nzaG2 * 0.9), 0.0, 1.0);
    float nzaGk = fract(nzaR1 * 7.31 + nzaR2 * 3.7);
    vec3 nzaGcol = mix(vec3(0.035, 0.03, 0.025), vec3(0.2, 0.16, 0.11), nzaGk * nzaGk);
    nzaGcol *= 0.55 + 0.45 * smoothstep(0.02, 0.1, min(nzaS1, nzaS2));
    nzaCol = mix(nzaCol, nzaGcol, nzaGrit);
    // water film darkens a little and saturates
    float nzaWater = clamp(nzaB.g, 0.0, 1.0);
    nzaCol = mix(nzaCol, pow(max(nzaCol, vec3(0.0)), vec3(1.12)) * 0.95, nzaWater * 0.7);
    nzaWet = clamp(max(max(nzaThin, nzaWater * 0.9), max(nzaInside * 0.92, nzaClf * 0.55)), 0.0, 1.0);
    diffuseColor.rgb *= nzaCol;
  `;
  const SKIN_ROUGH = `
    float roughnessFactor = uSkinRough * (0.8 + 0.4 * 0.5 * (nzaM1.b + nzaM2.b)) * (1.0 + 0.45 * nzaCav);
    roughnessFactor = mix(roughnessFactor, 0.86, smoothstep(0.05, 0.5, nzaGr));
    roughnessFactor = mix(roughnessFactor, 0.3, nzaInside);
    roughnessFactor = mix(roughnessFactor, 0.42, smoothstep(0.1, 0.4, nzaCl));
    roughnessFactor = mix(roughnessFactor, 0.16, max(nzaThin * 0.92, clamp(nzaB.g, 0.0, 1.0) * 0.75));
    roughnessFactor = mix(roughnessFactor, 0.92, nzaGrit);
    nzaSmooth = clamp(max(max(nzaInside * 0.8, nzaThick), max(nzaWet * 0.6, smoothstep(0.1, 0.4, nzaCl) * 0.9)), 0.0, 1.0);
  `;
  const SKIN_NORMAL = `
    vec3 nzaMn1 = texture2D(normalMap, nzaUv1).xyz * 2.0 - 1.0;
    vec3 nzaMn2 = texture2D(normalMap, nzaUv2).xyz * 2.0 - 1.0;
    nzaMn2.xy = nzaRot(nzaMn2.xy, -0.61);
    vec2 nzaMxy = 0.5 * (nzaMn1.xy + nzaMn2.xy) * uMicroNormal * (1.0 - nzaSmooth * 0.85);
    nzaMxy += (vec2(nzaN4.a, nzaN3.a) - 0.5) * 1.1 * nzaGrit;
    nzaMxy += (vec2(nzaN3.r, nzaN3.g) - 0.5) * 0.5 * nzaInside;
    // wound field relief
    float nzaHl = nzaFieldH(nzaW - vec2(uFieldTexel.x, 0.0));
    float nzaHr = nzaFieldH(nzaW + vec2(uFieldTexel.x, 0.0));
    float nzaHd = nzaFieldH(nzaW - vec2(0.0, uFieldTexel.y));
    float nzaHu = nzaFieldH(nzaW + vec2(0.0, uFieldTexel.y));
    vec2 nzaG = vec2((nzaHr - nzaHl) / (2.0 * uFieldTexel.x * uWork.x), (nzaHu - nzaHd) / (2.0 * uFieldTexel.y * uWork.y)) * 0.001 * uFieldNormal;
    // fluid films have thickness: meniscus highlights at the edges of pools and clots
    vec2 nzaLt = uLayerTexel * 1.5;
    float nzaFl = nzaFilm(nzaW - vec2(nzaLt.x, 0.0)), nzaFr = nzaFilm(nzaW + vec2(nzaLt.x, 0.0));
    float nzaFd = nzaFilm(nzaW - vec2(0.0, nzaLt.y)), nzaFu = nzaFilm(nzaW + vec2(0.0, nzaLt.y));
    vec2 nzaFG = vec2((nzaFr - nzaFl) / (2.0 * nzaLt.x * uWork.x), (nzaFu - nzaFd) / (2.0 * nzaLt.y * uWork.y)) * 0.001 * nzaWin;
    nzaFG = clamp(nzaFG, vec2(-1.2), vec2(1.2)) * (1.0 - 0.85 * nzaInside);
    // gentle large-scale undulation of the body surface
    float nzaU0 = texture2D(tNoise, nzaP * 3.0).r;
    float nzaUx = texture2D(tNoise, (nzaP + vec2(0.004, 0.0)) * 3.0).r;
    float nzaUy = texture2D(tNoise, (nzaP + vec2(0.0, 0.004)) * 3.0).r;
    vec2 nzaUG = vec2(nzaUx - nzaU0, -(nzaUy - nzaU0)) / 0.004 * 0.0016;
    vec3 nzaMacroN = perturbNormal2Arb(-vViewPosition, normal, normalize(vec3(-nzaG - nzaFG - nzaUG, 1.0)), faceDirection);
    normal = perturbNormal2Arb(-vViewPosition, normal, normalize(vec3(nzaMxy - nzaG - nzaFG * 0.7 - nzaUG, 1.0)), faceDirection);
  `;
  const SKIN_AO = `
    float nzaAO = 1.0 - smoothstep(0.0, 1.0, nzaDepthN) * 0.42;
    reflectedLight.indirectDiffuse *= nzaAO;
    reflectedLight.directDiffuse *= mix(1.0, nzaAO, 0.55);
    reflectedLight.indirectSpecular *= mix(1.0, nzaAO, 0.8);
    float nzaNdl = dot(normal, uKeyDir);
    float nzaWrap = clamp((nzaNdl + 0.5) / 1.5, 0.0, 1.0) - clamp(nzaNdl, 0.0, 1.0);
    reflectedLight.directDiffuse += max(nzaWrap, 0.0) * uKeyColor * vec3(0.9, 0.22, 0.12) * material.diffuseColor * uSSS * (1.0 - nzaInside);
    reflectedLight.indirectDiffuse += material.diffuseColor * vec3(0.05, 0.012, 0.006) * uSSS * (1.0 - nzaInside);
  `;

  const PART_VERT = `
    attribute float aSize;
    attribute float aAlpha;
    attribute vec3 aCol;
    uniform float uScale;
    varying float vA;
    varying vec3 vC;
    void main() {
      vec4 mv = modelViewMatrix * vec4(position, 1.0);
      gl_PointSize = clamp(aSize * uScale / max(-mv.z, 0.001), 1.0, 64.0);
      gl_Position = projectionMatrix * mv;
      vA = aAlpha; vC = aCol;
    }`;
  const PART_FRAG = `
    uniform sampler2D tDrop;
    varying float vA;
    varying vec3 vC;
    void main() {
      if (vA <= 0.001) discard;
      vec4 t = texture2D(tDrop, gl_PointCoord);
      gl_FragColor = vec4(vC * (0.55 + t.r * 0.6), t.a * vA);
    }`;
  const JET_VERT = `
    uniform vec3 p0; uniform vec3 p1; uniform vec3 p2; uniform float uRadius;
    varying float vT; varying vec3 vN; varying vec3 vView; varying float vAround;
    void main() {
      float t = position.y + 0.5;
      vec3 c = mix(mix(p0, p1, t), mix(p1, p2, t), t);
      vec3 T = normalize(2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1));
      vec3 up = abs(T.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
      vec3 N1 = normalize(cross(T, up)), N2 = cross(T, N1);
      vec2 xz = normalize(position.xz);
      vec3 nrm = xz.x * N1 + xz.y * N2;
      float r = uRadius * (1.0 - 0.18 * t) * (1.0 + 0.6 * smoothstep(0.9, 1.0, t));
      vec3 wp = c + nrm * r;
      vec4 mv = viewMatrix * vec4(wp, 1.0);
      vN = normalize((viewMatrix * vec4(nrm, 0.0)).xyz);
      vView = normalize(-mv.xyz);
      vT = t;
      vAround = atan(xz.y, xz.x);
      gl_Position = projectionMatrix * mv;
    }`;
  const JET_FRAG = `
    uniform float uTime; uniform float uAlpha;
    varying float vT; varying vec3 vN; varying vec3 vView; varying float vAround;
    void main() {
      float fres = pow(1.0 - abs(dot(vN, vView)), 1.6);
      float streak = 0.5 + 0.5 * sin(vT * 90.0 - uTime * 70.0 + vAround * 3.0);
      float a = (0.16 + 0.62 * fres + 0.14 * streak) * uAlpha * smoothstep(0.0, 0.04, vT);
      vec3 col = mix(vec3(0.78, 0.88, 0.95), vec3(1.0), fres * 0.7 + streak * 0.2);
      gl_FragColor = vec4(col, a);
    }`;

  window.NZA3D = {
    version: '1.0.0', MM, supported, createScene, release: releaseAll,
    tones: TONES.map(t => ({ at: t[0], rgb: t[1].slice() })), toneRGB,
    util: { rng, clamp, lerp, smooth, hash: hashStr, noiseAt },
  };
})();
