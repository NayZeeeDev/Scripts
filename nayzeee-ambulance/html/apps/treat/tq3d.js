/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · treat app · TOURNIQUET 3D                        window.TreatTq3D
   The treat app's 'tq' mode as a full-screen 3D close-up on core/nza3d.js (the suture / burn /
   bleed-control look) under the shared procedure HUD (NZA.ui.ProcPanel) and the treat context card.
   apps/treat/app.js starts it from open() when WebGL2 works; its 2D overlay (initTq) stays the
   fallback and runs unchanged when WebGL is missing or the scene fails to build.

   The limb   the wounded segment from the open data (region, limb, woundSeg, woundFrac) as an NZA3D
              limb patch (real skin: tone / sex / seed from the data, the engine's radius for that
              segment). The patch runs along the whole limb chain like the 2D rail: the root (groin /
              armpit) on the right, the joint (knee / elbow) and the wound to the left. Clothing covers
              the rest: a cut trouser leg / sleeve hem at the root, or for a forearm / lower-leg wound the
              trouser leg / sleeve rolled up to just above the joint (the strap may go over it, as in
              the field). Chain maths = the 2D tqSpot: t 0..1 along the limb, tj = the joint,
              cm above the wound = (tw - t) · tune.length; jointZone, idealAbove, high-and-tight
              (< 35 % down the upper segment) and "below the wound" (< 1.5 cm above) are the same.
   The device a generic windlass tourniquet built here with THREE (no name, no brand): black nylon
              webbing band with a hook-and-loop free end and a red pull tab, a plastic buckle, a
              windlass plate with a teal rod, two C-hooks (the clip) and a short windlass strap that
              carries the white TIME label. Everything is freed on close (S.dispose + this file's bin).

   Steps (the step column shows four; the result keeps the 2D's three scores place / twist / lock):
     1 place   grab the tourniquet lying beside the limb and drag the loop onto the limb above the
               wound (teal bands = 5–8 cm above the wound and high-and-tight; red band = the joint).
               Let go to place it: a valid spot posts treat:tqPlace { seg, frac } (exactly the 2D
               post); below the wound / on the joint counts a misplacement and the loop stays loose
               where it fell (drag it again); dropped off the limb it goes back.
     2 slack   drag the red tab on the free end away from the buckle: the loop closes on the limb.
               Let go inside the green band (2D: release ≥ 0.62 counts, 0.75–1.0 is good, > 1 yanked).
     3 twist   hold LMB on the rod and turn it round (circular drag: the rod follows the cursor). Each
               turn adds tune.turnGain mmHg; the bleeding slows and stops, the distal pulse goes, the
               patient's pain rises; past occlusion + overMargin it is over-tightened. Let go and the
               rod slowly unwinds (tune.unwind mmHg/s). Done when the bleeding has stopped for 0.7 s.
     4 lock    keep turning until the rod lines up with the clip (clipWindow°, the hooks light up) and
               let go: it drops into the clip (or E / Space / click the clip; a miss counts a misLock).
               The windlass strap folds over it; then write the time on the label (hold LMB and
               scribble across it, or press E). Then treat:finish.
   Lua → JS   the app's own messages (open, vitals, result); open data may carry tone + seed and
              resume (a step-away snapshot)
   JS → Lua   through the app, exactly the 2D posts and values: treat:tqPlace { seg, frac (3 dp) } ·
              treat:finish { result: { score, seg, frac, pressure, over, misLocks, time,
              steps: { place, twist, lock } } } (same formulas as finishTq) · treat:abort {}.
              Timing: real-time steps (twist time from the game clock), the server's minTime /
              maxTime are untouched (the client waits out minTime, a resumed run keeps its time).
   Step away  P / "Step away" on the HUD (ProcPanel opts.pause = snapshot()): returns null while a
              move is half done (carrying the strap, pulling, holding the rod, writing). snapshot =
              { v, w (limb + wound it belongs to), k (step), t, lost, q (strap spot, scores, slack,
              pressure, rod angle, over, misLocks, twist time, locked, written, time) }; on open with
              data.resume the same point is rebuilt (a resumed placement posts treat:tqPlace again so
              the strap prop is back on the ped); unreadable fields fall back to the step start, a
              snapshot of another limb / wound starts afresh. The game counts no consumables (the
              tourniquet itself is taken by the server on finish), so there is no "out of" message.
   Preview    index.html?app=treat&mode=tq&stage=place|slack|twist|lock|write|done
              &resume=<stage> (plays to that point, steps away and opens again from the snapshot;
              P in the preview parks it, "Reopen" carries on) · &site=thigh|leg|arm|forearm
              &wound=gunshot|stab|laceration|shrapnel  &noinj=1 (precaution: no wound)
              &tone=0..1  &sex=m|f  &no3d=1 (2D fallback)
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
  const angDiff = (a, b) => { let d = (a - b) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; };
  // tolerant number reader for snapshots (null / '' / booleans / NaN → fallback)
  const num = (v, fb) => { if (v === null || v === undefined || v === '' || typeof v === 'boolean') return fb; const n = Number(v); return Number.isFinite(n) ? n : fb; };
  const rnd = (v, k) => { const m = Math.pow(10, k); return Math.round(v * m) / m; };
  const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]|%\.\df/, v); }); return s; };

  // anatomy per limb: segment lengths (cm → the joint's place on the chain), the engine's limb radii (m)
  const KIND = {
    leg: { L1: 44, L2: 42, R1: 0.075, R2: 0.055, cloth: [44, 62, 92], len: 88 },
    arm: { L1: 30, L2: 26, R1: 0.05, R2: 0.04, cloth: [58, 62, 68], len: 62 },
  };
  const TONES = [0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88];
  const BLOOD = [0.36, 0.012, 0.014];
  const BW = 0.038, TH = 0.0024;                        // band width / thickness (outer band + inner windlass band)
  const ROD_L = 0.09, ROD_R = 0.0042;                   // windlass rod
  const PLX = 0.036, PLZ = 0.0175, PLY = 0.0032;        // windlass plate: half-length along the limb, half-width along the band, thickness
  const HOOK_X = 0.0305, HOOK_R = ROD_R + 0.001, HOOK_T = 0.0015, HOOK_GAP = 1.9;
  const H_LOCK = PLY + 0.0036 + ROD_R;                  // rod axis above the band when it sits in the clip
  const H_TURN = H_LOCK + 0.0102;                       // … while it turns (clear of the hook tips)
  const A_W = 0.22, A_B = 0.74;                          // loop angles: windlass, buckle (0 = top of the limb, + toward you)
  const SLACK_PX = 0.15;                                // screen heights of drag per full pull of the free end
  const MAX_SNAP_T = 3600;
  let PARKED = null;            // preview: the snapshot "Step away" kept (Reopen carries on from it)
  let PREVIEW_MOCKED = false;   // preview: the '_proc:pause' mock is installed once per page
  let PREVIEW_RESUMED = false;  // preview: ?resume=<stage> runs once per page

  /* ═════════════════════════════ CSS (stage, cursor ring, tags, loading veil) ═════════════════════════════ */
  const CSS = `
#app-treat .tq3-stage{position:absolute;inset:0;overflow:hidden;cursor:crosshair;pointer-events:auto;background:#050607}
#app-treat .tq3-stage.grab{cursor:grab}
#app-treat .tq3-stage.grabbing{cursor:grabbing}
#app-treat .tq3-stage.hide{cursor:none}
#app-treat .tq3-stage.point{cursor:pointer}
#app-treat .tq3-cur{position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;opacity:0;transition:opacity 140ms;z-index:3}
#app-treat .tq3-cur.on{opacity:1}
#app-treat .tq3-cur svg{position:absolute;left:-23px;top:-23px;width:46px;height:46px;transform:rotate(-90deg)}
#app-treat .tq3-cur.noring svg{display:none}
#app-treat .tq3-cur .bg{stroke:rgba(255,255,255,.22);fill:none;stroke-width:3}
#app-treat .tq3-cur .fg{stroke:var(--teal-hi);fill:none;stroke-width:3;stroke-linecap:round;filter:drop-shadow(0 0 4px rgba(15,212,196,.7))}
#app-treat .tq3-cur.red .fg{stroke:#ff7478;filter:drop-shadow(0 0 4px rgba(229,72,77,.7))}
#app-treat .tq3-cur.amber .fg{stroke:#f3c35a;filter:drop-shadow(0 0 4px rgba(229,165,10,.6))}
#app-treat .tq3-cur .tx{position:absolute;left:30px;top:-11px;height:22px;display:inline-flex;align-items:center;padding:0 8px;border-radius:6px;white-space:nowrap;
  font:600 11px var(--font);color:var(--white);background:rgba(12,13,16,.86);border:1px solid var(--hud-line)}
#app-treat .tq3-cur.noring .tx{left:16px}
#app-treat .tq3-cur .tx:empty{display:none}
#app-treat .tq3-cur.teal .tx{color:var(--teal-hi)} #app-treat .tq3-cur.red .tx{color:#ff9a9d} #app-treat .tq3-cur.amber .tx{color:#f3c35a}
#app-treat .tq3-tag{position:fixed;left:0;top:0;pointer-events:none;opacity:0;transition:opacity 180ms;z-index:2}
#app-treat .tq3-tag.on{opacity:1}
#app-treat .tq3-tag b{position:absolute;left:0;top:0;transform:translate(-50%,-50%);display:inline-flex;align-items:center;gap:7px;height:24px;padding:0 10px 0 9px;border-radius:7px;white-space:nowrap;
  font:600 11px var(--font);letter-spacing:.02em;color:#f4f6f2;background:linear-gradient(rgba(26,28,32,.94),rgba(10,11,13,.94));border:1px solid rgba(255,255,255,.14);box-shadow:0 5px 16px rgba(0,0,0,.55)}
#app-treat .tq3-tag b i{width:7px;height:7px;transform:rotate(45deg);background:rgba(255,255,255,.75);flex:none}
#app-treat .tq3-tag.red b{border-color:rgba(255,90,96,.55)} #app-treat .tq3-tag.red b i{background:#ff5a60;box-shadow:0 0 8px #ff5a60}
#app-treat .tq3-tag.teal b{border-color:rgba(15,212,196,.55)} #app-treat .tq3-tag.teal b i{background:#0fd4c4;box-shadow:0 0 8px #0fd4c4}
#app-treat .tq3-tag.amber b{border-color:rgba(243,195,90,.55)} #app-treat .tq3-tag.amber b i{background:#f3c35a}
#app-treat .tq3-load{position:absolute;inset:0;display:grid;place-items:center;background:#050607;transition:opacity 260ms;pointer-events:none}
#app-treat .tq3-load.out{opacity:0}
#app-treat .tq3-load .in{display:flex;flex-direction:column;align-items:center;gap:12px;color:var(--ink-3);font-size:12px}
#app-treat .tq3-load .ring{width:34px;height:34px;border-radius:50%;border:3px solid rgba(255,255,255,.1);border-top-color:var(--teal);animation:tq3-spin 900ms linear infinite}
@keyframes tq3-spin{to{transform:rotate(360deg)}}`;
  function injectCss() {
    if (document.getElementById('tq3-css')) return;
    const s = document.createElement('style');
    s.id = 'tq3-css'; s.textContent = CSS;
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
  // nylon webbing: tight twill ribs along the band, a fuzzy loop-pile strip down the middle of the
  // outer face (the hook-and-loop), denser selvedges. u = along the band (one tile ≈ 4 cm), v = across
  function webbingTex() {
    if (TEX.web) return TEX.web;
    const W = 256, H = 128, h = cvs(W, H), x = h.getContext('2d'), a = cvs(W, H), ax = a.getContext('2d'), r = rng(4242);
    x.fillStyle = '#7a7a7a'; x.fillRect(0, 0, W, H);
    ax.fillStyle = '#1d1e20'; ax.fillRect(0, 0, W, H);
    // twill ribs (diagonal, fine)
    for (let k = -H; k < W + H; k += 4) {
      const v = 120 + r() * 70;
      x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = 1.8;
      x.beginPath(); x.moveTo(k, 0); x.lineTo(k + H * 0.45, H); x.stroke();
      const c = 26 + r() * 10;
      ax.strokeStyle = `rgba(${c},${c},${c + 2},0.9)`; ax.lineWidth = 1.4;
      ax.beginPath(); ax.moveTo(k, 0); ax.lineTo(k + H * 0.45, H); ax.stroke();
    }
    // loop pile in the middle: soft fuzz (matte, a touch lighter)
    for (let i = 0; i < 2600; i++) {
      const px = r() * W, py = H * (0.2 + r() * 0.6), L = 1 + r() * 3, ang = r() * TAU;
      const v = 140 + r() * 90;
      x.strokeStyle = `rgba(${v},${v},${v},0.5)`; x.lineWidth = 1;
      x.beginPath(); x.moveTo(px, py); x.lineTo(px + Math.cos(ang) * L, py + Math.sin(ang) * L); x.stroke();
      const c = 34 + r() * 18;
      ax.strokeStyle = `rgba(${c},${c},${c + 3},0.55)`; ax.lineWidth = 1;
      ax.beginPath(); ax.moveTo(px, py); ax.lineTo(px + Math.cos(ang) * L, py + Math.sin(ang) * L); ax.stroke();
    }
    // selvedges: two tight ridges at each edge, and a stitch line holding the inner band
    for (const y0 of [3, H - 9]) {
      x.fillStyle = 'rgba(210,210,210,0.7)'; x.fillRect(0, y0, W, 2); x.fillRect(0, y0 + 4, W, 2);
      ax.fillStyle = 'rgba(14,14,15,0.9)'; ax.fillRect(0, y0, W, 6);
    }
    for (const y0 of [H * 0.16, H * 0.84]) {
      for (let k = 0; k < W; k += 8) { x.fillStyle = 'rgba(220,220,220,.8)'; x.fillRect(k, y0 - 1, 5, 2); ax.fillStyle = 'rgba(52,53,56,.9)'; ax.fillRect(k, y0 - 1, 5, 2); }
    }
    TEX.web = { albedo: a, normal: heightToNormal(h, 2.2) };
    return TEX.web;
  }
  // clothing: denim / cotton twill (albedo tinted per limb, normal shared). One tile ≈ 5 cm
  function clothTex(rgb) {
    const key = `cloth:${rgb.join(',')}`;
    if (TEX[key]) return TEX[key];
    const n = 256, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(77);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    ax.fillStyle = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`; ax.fillRect(0, 0, n, n);
    const step = n / 64;
    for (let k = -n; k < 2 * n; k += step) {
      const v = 110 + r() * 80;
      x.strokeStyle = `rgba(${v},${v},${v},0.8)`; x.lineWidth = step * 0.55;
      x.beginPath(); x.moveTo(k, 0); x.lineTo(k + n * 0.6, n); x.stroke();
      const f = 0.82 + r() * 0.36;
      ax.strokeStyle = `rgba(${Math.round(rgb[0] * f)},${Math.round(rgb[1] * f)},${Math.round(rgb[2] * f)},0.6)`; ax.lineWidth = step * 0.5;
      ax.beginPath(); ax.moveTo(k, 0); ax.lineTo(k + n * 0.6, n); ax.stroke();
    }
    // slubs, fading, lint
    for (let i = 0; i < 900; i++) {
      const px = r() * n, py = r() * n, L = 2 + r() * 8;
      ax.strokeStyle = `rgba(255,255,255,${0.03 + r() * 0.06})`; ax.lineWidth = 1;
      ax.beginPath(); ax.moveTo(px, py); ax.lineTo(px + L * 0.6, py + L); ax.stroke();
    }
    TEX[key] = { albedo: a, normal: heightToNormal(h, 1.6) };
    return TEX[key];
  }
  // a band round the limb: soft fill + dashed edges (white: tinted by the material)
  function zoneTex() {
    if (TEX.zone) return TEX.zone;
    const W = 512, H = 64, c = cvs(W, H), x = c.getContext('2d');
    const g = x.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, 'rgba(255,255,255,.34)'); g.addColorStop(0.18, 'rgba(255,255,255,.12)'); g.addColorStop(0.82, 'rgba(255,255,255,.12)'); g.addColorStop(1, 'rgba(255,255,255,.34)');
    x.fillStyle = g; x.fillRect(0, 0, W, H);
    x.fillStyle = '#fff';
    for (let k = 0; k < W; k += 32) { x.fillRect(k, 0, 18, 5); x.fillRect(k, H - 5, 18, 5); }
    TEX.zone = c;
    return c;
  }
  // contact shadow across a strip: dark under the band edges, fading out (alpha in the green channel)
  function contactTex() {
    if (TEX.contact) return TEX.contact;
    const W = 4, H = 128, c = cvs(W, H), x = c.getContext('2d');
    const g = x.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, 'rgb(0,0,0)'); g.addColorStop(0.18, 'rgb(150,150,150)'); g.addColorStop(0.28, 'rgb(255,255,255)');
    g.addColorStop(0.72, 'rgb(255,255,255)'); g.addColorStop(0.82, 'rgb(150,150,150)'); g.addColorStop(1, 'rgb(0,0,0)');
    x.fillStyle = g; x.fillRect(0, 0, W, H);
    TEX.contact = c;
    return c;
  }
  // dashed guide circle with four arrowheads (the windlass turning guide)
  function guideTex() {
    if (TEX.guide) return TEX.guide;
    const N = 256, c = cvs(N, N), x = c.getContext('2d'), m = N / 2, R = 108;
    x.strokeStyle = '#fff'; x.lineCap = 'round'; x.lineWidth = 3.5;
    for (let i = 0; i < 36; i++) { x.beginPath(); x.arc(m, m, R, (i / 36) * TAU, (i / 36 + 0.012) * TAU); x.stroke(); }
    x.fillStyle = '#fff';
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * TAU + 0.3, px = m + Math.cos(a) * R, py = m + Math.sin(a) * R, d = a + Math.PI / 2;
      x.beginPath(); x.moveTo(px + Math.cos(d) * 9, py + Math.sin(d) * 9);
      x.lineTo(px - Math.cos(d) * 4 + Math.cos(a) * 6, py - Math.sin(d) * 4 + Math.sin(a) * 6);
      x.lineTo(px - Math.cos(d) * 4 - Math.cos(a) * 6, py - Math.sin(d) * 4 - Math.sin(a) * 6); x.closePath(); x.fill();
    }
    TEX.guide = c;
    return c;
  }
  // plastic grain (windlass parts)
  function grainTex() {
    if (TEX.grain) return TEX.grain;
    const n = 128, c = cvs(n, n), x = c.getContext('2d'), r = rng(9);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < 2600; i++) { const v = 105 + r() * 50; x.fillStyle = `rgb(${v},${v},${v})`; x.fillRect(r() * n, r() * n, 1 + r() * 1.5, 1 + r() * 1.5); }
    TEX.grain = heightToNormal(c, 1.2);
    return TEX.grain;
  }

  /* ═════════════════════════════ geometry helpers ═════════════════════════════ */
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
  // closed tube round a loop: NA rings × NP profile points (a rounded rectangle BW × TH, superellipse)
  const NP = 16, PROF = [];
  for (let k = 0; k < NP; k++) {
    const ph = (k / NP) * TAU, c = Math.cos(ph), s = Math.sin(ph), e = 2 / 10;
    const x = Math.sign(c) * Math.pow(Math.abs(c), e) * BW / 2, h = Math.sign(s) * Math.pow(Math.abs(s), e) * TH / 2;
    // superellipse normal ∝ (sgn c |c|^(2-e) / a, sgn s |s|^(2-e) / b)
    let nx = Math.sign(c) * Math.pow(Math.abs(c), 2 - e) / (BW / 2), nh = Math.sign(s) * Math.pow(Math.abs(s), 2 - e) / (TH / 2);
    const L = Math.hypot(nx, nh) || 1; nx /= L; nh /= L;
    PROF.push({ x, h, nx, nh, v: x / BW + 0.5 });
  }
  function loopTubeGeo(NA) {
    const g = new THREE.BufferGeometry(), nv = NA * NP;
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(nv * 2), 2).setUsage(THREE.DynamicDrawUsage));
    const idx = [];
    for (let j = 0; j < NA; j++) {
      for (let i = 0; i < NP; i++) {
        const a = j * NP + i, b = j * NP + ((i + 1) % NP), c = ((j + 1) % NA) * NP + i, d = ((j + 1) % NA) * NP + ((i + 1) % NP);
        idx.push(a, b, c, b, d, c);
      }
    }
    g.setIndex(idx);
    return g;
  }
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

  /* ═════════════════════════════ preview data (browser only) ═════════════════════════════ */
  const SITES = {
    thigh: ['l_upper_leg', 'Left thigh', 'leg', 'upper', 0.62], leg: ['r_lower_leg', 'Right lower leg', 'leg', 'lower', 0.45], shin: ['r_lower_leg', 'Right lower leg', 'leg', 'lower', 0.45],
    arm: ['r_upper_arm', 'Right upper arm', 'arm', 'upper', 0.6], forearm: ['l_lower_arm', 'Left forearm', 'arm', 'lower', 0.45],
  };
  const TYPE_LABEL = { gunshot: 'Gunshot wound', stab: 'Stab wound', laceration: 'Deep laceration', shrapnel: 'Shrapnel wounds' };
  function previewTweak(d) {
    if (NZA.inGame) return;
    const q = new URLSearchParams(location.search);
    const site = SITES[q.get('site')];
    if (site) {
      Object.assign(d, { region: site[0], regionLabel: site[1], limb: site[2], woundSeg: site[3], woundFrac: site[4] });
      if (d.injury) d.injury = Object.assign({}, d.injury, { region: site[0], regionLabel: site[1], limb: site[2], frac: site[4] });
      d.tune = Object.assign({}, d.tune || {}, site[2] === 'arm' ? { length: 62, occlusion: 160, turnGain: 65 } : { length: 88 });
    }
    const w = q.get('wound');
    if (w && TYPE_LABEL[w] && d.injury) d.injury = Object.assign({}, d.injury, { type: w, typeLabel: TYPE_LABEL[w] });
    if (q.get('noinj') === '1') d.injury = null;
    if (q.get('tone') !== null) d.tone = clamp(+q.get('tone') || 0, 0, 1);
    if (q.get('sex')) d.patient = Object.assign({}, d.patient || {}, { sex: q.get('sex') === 'f' ? 'f' : 'm' });
    // "Step away" in the browser: keep the snapshot and close; Reopen carries on from it (in game:
    // using the same option again within Config.ProcPause.keep). A test may replace this mock.
    if (!PREVIEW_MOCKED) {
      PREVIEW_MOCKED = true;
      NZA.mock('_proc:pause', r => { PARKED = r && r.snapshot; setTimeout(() => NZA.close('treat'), 80); return { ok: true }; });
    }
    if (PARKED && !d.resume) { d.resume = PARKED; PARKED = null; }
  }

  /* ═════════════════════════════ THE GAME ═════════════════════════════ */
  class Game {
    constructor(app, data) {
      this.app = app; this.d = data;
      LOC = Object.assign({}, data.locale || {});
      previewTweak(data);
      const kind = data.limb === 'arm' || (data.limb !== 'leg' && /arm/.test(String(data.region || ''))) ? 'arm' : 'leg';
      this.kind = kind; this.K = KIND[kind];
      const t0 = Object.assign({ occlusion: 220, turnGain: 65, overMargin: 110, unwind: 22, clipWindow: 14, jointZone: 0.1, idealAbove: [5, 8], length: this.K.len }, data.tune || {});
      this.tune = {
        occlusion: Math.max(40, num(t0.occlusion, 220)), turnGain: Math.max(5, num(t0.turnGain, 65)), overMargin: Math.max(10, num(t0.overMargin, 110)),
        unwind: Math.max(0, num(t0.unwind, 22)), clipWindow: clamp(num(t0.clipWindow, 14), 2, 45), jointZone: clamp(num(t0.jointZone, 0.1), 0, 0.4),
        idealAbove: Array.isArray(t0.idealAbove) ? [num(t0.idealAbove[0], 5), num(t0.idealAbove[1], 8)] : [5, 8], length: clamp(num(t0.length, this.K.len), 30, 140),
      };
      this.KEY = Object.assign({ confirm: 'Space', lock: 'KeyE', done: 'Enter' }, data.keys || {});
      const G = this.G = app.G;
      G.b = data.injury ? 1 : 0; G.maxB = 1; G.pulseAmp = 1;
      this.q = { t: 0.2, placed: false, seg: null, frac: null, slack: 0, P: 0, theta: 0, locked: false, over: 0, misLocks: 0, misplaced: 0, placeScore: 100, slackScore: 0, twistTime: null, time: typeof data.time === 'string' ? data.time : '', written: 0 };
      this.steps = ['place', 'slack', 'twist', 'lock'];
      this.alive = true; this.ready = false; this.stepIdx = -1; this.t = 0; this.lmb = false; this.uiAt = 0;
      this.cur = { p: null, text: '', tone: '' };
      this.rodDir = 0; this.rodGrab = null; this.carry = null; this.anim = null;
      this.bin = new Set();
      // the app shell: an opaque full-screen close-up, no game-camera input, no 2D stage / device
      app.full = true; app.opaque = true; app.camInput = false;
      app.el.classList.add('nza-full');
      if (app.cv) app.cv.style.display = 'none';
      if (app.dev) app.dev.classList.remove('on');
      injectCss();
      this.stage = el('div', 'tq3-stage');
      app.root.insertBefore(this.stage, app.root.firstChild);
      this.curEl = el('div', 'tq3-cur', '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>');
      app.root.appendChild(this.curEl);
      this.curFg = this.curEl.querySelector('.fg'); this.curTx = this.curEl.querySelector('.tx');
      this.tags = {};
      this.loadEl = el('div', 'tq3-load', `<div class="in"><span class="ring"></span><span>${NZA.esc(T('b3_loading', 'Preparing the close-up…'))}</span></div>`);
      app.root.appendChild(this.loadEl);
      app.setTip(T('tip_tq', '**High and tight:** 5–8 cm above the wound, never over a joint. If you are unsure, go high on the upper arm / thigh.'));
      // keys reach the game through the app's phase hook; the tool belt through onTool; "Step away" (P)
      app.ph = { key: e => this.key(e), keyUp: () => false };
      this.pauseFn = () => this.snapshot();
      app.pp.set({ onTool: k => this.pickTool(k), pause: this.pauseFn });
      this.onBlur = () => { if (this.lmb) this.up({ button: 0 }); };
      this.onResize = () => { this.zoom = 0; };
      window.addEventListener('blur', this.onBlur);
      window.addEventListener('resize', this.onResize);
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive) this.boot(); }));
    }

    keep(x) { if (x) this.bin.add(x); return x; }

    /* ─────────────── layout: the limb chain on the patch ─────────────── */
    layout() {
      const d = this.d, K = this.K, tune = this.tune;
      const reg = String(d.region || '');
      const key = reg.replace(/^[lr]_/, '');
      let seg = d.woundSeg === 'lower' || d.woundSeg === 'upper' ? d.woundSeg : (/^lower/.test(key) ? 'lower' : 'upper');
      this.region = /^(upper|lower)_(arm|leg)$/.test(key) && key.endsWith(this.kind) ? reg : `${/^r_/.test(reg) ? 'r' : 'l'}_${seg}_${this.kind}`;
      this.wSeg = seg;
      this.wFrac = clamp(num(d.woundFrac, 0.5), 0, 1);
      this.Rs = seg === 'upper' ? K.R1 : K.R2;
      this.tj = K.L1 / (K.L1 + K.L2);
      this.Lm = tune.length / 100;
      this.jz = tune.jointZone;
      this.tw = this.tOf(seg, this.wFrac);
      this.lowerWound = seg === 'lower';
      // clothing: a hem at the root, or (forearm / lower leg) rolled up to just above the joint
      this.tCov = this.lowerWound ? Math.max(0.06, this.tj * (1 - this.jz) - 0.035) : 0.012;
      const jointEnd = this.tj + (1 - this.tj) * this.jz;
      this.tEnd = Math.min(1, Math.max(this.tw, jointEnd) + 0.17);
      const rootM = 0.08;
      this.W = (this.tEnd + rootM) * this.Lm;
      this.H = TAU * this.Rs * 0.995;
      this.sRoot = this.W / 2 - rootM * this.Lm;
      this.sCov = this.sOf(this.tCov);
      this.tMin = 0.02; this.tMax = this.tEnd - 0.05;
      const spot = (d.injury && d.injury.spot) || { x: 0.5, y: 0.5 };
      this.wA = 0.36 + clamp(num(spot.x, 0.5) - 0.5, -0.3, 0.3) * 0.5;
      this.wS = this.sOf(this.tw);
      this.wUv = [this.wS / this.W + 0.5, 0.5 - (this.wA * this.Rs) / this.H];
    }
    sOf(t) { return this.sRoot - t * this.Lm; }
    tOfS(s) { return (this.sRoot - s) / this.Lm; }
    tOf(seg, frac) { return seg === 'upper' ? frac * this.tj : this.tj + frac * (1 - this.tj); }
    segOf(t) { return t <= this.tj ? { seg: 'upper', frac: t / this.tj } : { seg: 'lower', frac: (t - this.tj) / (1 - this.tj) }; }
    // the 2D tqSpot: where the strap sits relative to the wound and the joint
    spot(t) {
      const s = this.segOf(t), jz = this.jz;
      const cm = (this.tw - t) * this.tune.length;
      const onJoint = (s.seg === 'upper' && s.frac > 1 - jz) || (s.seg === 'lower' && s.frac < jz);
      const highTight = s.seg === 'upper' && s.frac < 0.35;
      const noWound = !this.d.injury;
      return { cm, onJoint, highTight, seg: s.seg, frac: s.frac, below: !noWound && cm < 1.5, noWound };
    }
    // the 2D confirm() score of a placement
    placeScoreFor(sp) {
      let sc = 100;
      if (!sp.noWound && !sp.highTight) {
        const lo = this.tune.idealAbove[0], hi = this.tune.idealAbove[1];
        if (sp.cm < lo) sc = 70; else if (sp.cm > hi * 3) sc = 82; else if (sp.cm > hi) sc = 92;
        if (sp.seg === 'lower') sc -= 8;
      }
      return clamp(sc - this.q.misplaced * 12, 0, 100);
    }
    spotText(sp) {
      if (sp.noWound) return sp.onJoint ? T('lbl_joint', 'On the joint') : sp.highTight ? T('lbl_high', 'High and tight') : T('lbl_lower', 'Lower on the limb');
      if (sp.below) return T('lbl_below', 'Below the wound');
      if (sp.onJoint) return T('lbl_joint', 'On the joint');
      if (sp.highTight) return T('lbl_high', 'High and tight');
      return T('lbl_cm', '%s cm above the wound', Math.max(0, Math.round(sp.cm)));
    }
    spotTone(sp) {
      if (sp.below || sp.onJoint) return 'red';
      if (sp.highTight || (!sp.noWound && sp.cm >= this.tune.idealAbove[0] && sp.cm <= this.tune.idealAbove[1])) return 'teal';
      return 'amber';
    }
    // where a strap belongs: the middle of 5–8 cm above the wound (off the joint), else high and tight
    tIdeal() {
      const hiT = 0.17 * this.tj;
      if (!this.d.injury) return hiT;
      const mid = (this.tune.idealAbove[0] + this.tune.idealAbove[1]) / 2;
      const t = clamp(this.tw - mid / this.tune.length, this.tMin, this.tMax);
      const sp = this.spot(t);
      return sp.onJoint || sp.below ? hiT : t;
    }
    // radius the band wraps at s: bare skin, or the clothing (thicker over the thigh / upper arm)
    clothR(s) {
      const d = s - this.sCov;
      const up = (this.lowerWound ? this.K.R1 : this.Rs) + 0.006;
      return lerp(this.Rs + 0.0068, up, smooth(0.0, 0.16, d)) + 0.0062 * Math.exp(-Math.pow((d - 0.006) / 0.0075, 2));
    }
    baseR(s) { return s > this.sCov - 0.002 ? this.clothR(Math.max(s, this.sCov)) + 0.0018 : this.Rs; }
    onCloth(s) { return s > this.sCov - 0.002; }

    /* ─────────────── scene ─────────────── */
    boot() {
      const d = this.d, inj = d.injury || null;
      const name = (d.patient && d.patient.name) || '';
      this.layout();
      const seed = (num(d.seed, 0) || hash(`${this.region}:${inj ? inj.id : ''}:${name}`)) >>> 0;
      this.seed = seed; this.R = rng(seed);
      const tone = d.tone !== undefined && d.tone !== null && d.tone !== '' ? clamp(num(d.tone, 0.3), 0, 1) : TONES[hash(name || this.region) % TONES.length];
      const sex = (d.patient && d.patient.sex) === 'f' ? 'f' : 'm';
      this.sev = clamp(Math.round(num(inj && inj.severity, 2)), 1, 4);
      const focus = inj ? this.wUv : [this.sOf(this.tIdeal()) / this.W + 0.5, 0.5];
      // 'medium' = what the in-game cap (Config.UI.quality3d 'auto') gives anyway: the preview shows the real look
      const opts = { tone, region: this.region, sex, seed, quality: (d.cfg && d.cfg.quality) || 'medium', size: [this.W, this.H], work: [0.3, Math.min(this.H, 0.26)] };
      opts.focus = { uv: focus, size: [0.08, 0.05], view: 0.4 };
      let S;
      try { S = NZA3D.createScene(this.stage, opts); } catch (e) { console.error('[treat] tq 3D scene', e); return this.fail(); }
      this.S = S;
      if (S.shape && S.shape.R && Math.abs(S.shape.R - this.Rs) > 1e-4) this.Rs = S.shape.R;
      S.controls.limits.pitchMin = 0.5;
      if (S._cloth) S._cloth.material.color.setHex(0x2b3a40);
      this.clothY = S._cloth ? S._cloth.position.y : -this.Rs * 1.55;
      this.rc = new THREE.Raycaster();
      try {
        this.M = this.materials();
        if (inj) { this.makeWound(); this.paintInitial(); }
        this.makeClothing();
        this.makeZones();
        this.makeTq();
        this.makePen();
      } catch (e) { console.error('[treat] tq 3D build', e); return this.fail(); }
      S.layers.decay('wet', 0.05);
      this.prewarm();
      S.on('frame', (dt, render) => this.frame(dt, render !== false));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.on('pointer', () => this.pointer());
      S.start();
      this.ready = true;
      // carrying on after "Step away": rebuild the saved point (a bad snapshot never stops the game)
      let snap = d.resume && typeof d.resume === 'object' && !Array.isArray(d.resume) ? d.resume : null, other = false, done = false;
      if (snap && !this.sameLimb(snap.w)) { other = true; snap = null; }
      if (snap) {
        try { done = this.restore(snap); } catch (e) { console.error('[treat] tq restore', e); done = false; }
        if (!done) { this.resetGame(); }
      }
      if (!done) { this.stepIdx = -1; this.nextStep(); }
      if (done) setTimeout(() => { if (this.alive && !this.finished) this.app.pp.flash('ok', T('tq3_resume', 'Carrying on where you left off.'), 3200); }, 300);
      else if (other) setTimeout(() => { if (this.alive) this.app.pp.flash('warn', T('tq3_resume_other', 'You stepped away from a different limb: this one starts from the beginning.'), 4200); }, 300);
      setTimeout(() => this.loadEl && this.loadEl.classList.add('out'), 140);
      if (this.pendingJump) { const j = this.pendingJump; this.pendingJump = null; this.jump(j); }
      // preview: ?resume=<stage> plays to that point, steps away and carries on from the snapshot
      if (!NZA.inGame && !d.resume && !PREVIEW_RESUMED) {
        const st = new URLSearchParams(location.search).get('resume');
        if (st) { PREVIEW_RESUMED = true; setTimeout(() => { if (this.alive) this.previewPark(st); }, 120); }
      }
    }

    // 3D could not start after all: hand the session to the 2D game (unchanged)
    fail() {
      const a = this.app;
      this.dispose();
      a.b3 = null;
      if (a.cv) a.cv.style.display = '';
      if (a.dev) a.dev.classList.add('on');
      a.ph = null;
      a.pp.set({ onTool: () => {}, pause: false });
      a.initTq(); a.renderCard();
      a.last = performance.now();
      const loop = () => { a.raf = requestAnimationFrame(loop); a.frame(); };
      a.raf = requestAnimationFrame(loop);
    }

    materials() {
      const keep = x => this.keep(x);
      const tex = (c, srgb, rep) => { const t = keep(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; if (srgb) t.encoding = THREE.sRGBEncoding; if (rep) t.repeat.set(rep[0], rep[1]); return t; };
      const wb = webbingTex(), ct = clothTex(this.K.cloth);
      const grain = tex(grainTex(), false, [3, 3]);
      const M = {
        band: keep(new THREE.MeshPhysicalMaterial({ map: tex(wb.albedo, true), normalMap: tex(wb.normal, false), normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.74, sheen: 0.55, sheenRoughness: 0.45, sheenColor: new THREE.Color(0x7d838c), envMapIntensity: 0.7 })),
        tail: keep(new THREE.MeshPhysicalMaterial({ map: tex(wb.albedo, true), normalMap: tex(wb.normal, false), normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.78, sheen: 0.5, sheenRoughness: 0.5, sheenColor: new THREE.Color(0x7d838c), side: THREE.DoubleSide, envMapIntensity: 0.7 })),
        plastic: keep(new THREE.MeshPhysicalMaterial({ color: 0x030304, roughness: 0.5, normalMap: grain, normalScale: new THREE.Vector2(0.25, 0.25), clearcoat: 0.18, clearcoatRoughness: 0.45, envMapIntensity: 0.8 })),
        hook: keep(new THREE.MeshPhysicalMaterial({ color: 0x040405, roughness: 0.45, clearcoat: 0.2, clearcoatRoughness: 0.4, emissive: new THREE.Color(0x0fd4c4), emissiveIntensity: 0 })),
        rod: keep(new THREE.MeshPhysicalMaterial({ color: 0x127f70, roughness: 0.38, normalMap: grain, normalScale: new THREE.Vector2(0.18, 0.18), clearcoat: 0.55, clearcoatRoughness: 0.25 })),
        grip: keep(new THREE.MeshPhysicalMaterial({ color: 0x06463e, roughness: 0.6 })),
        buckle: keep(new THREE.MeshPhysicalMaterial({ color: 0x07080a, roughness: 0.42, metalness: 0.2, clearcoat: 0.2 })),
        tab: keep(new THREE.MeshPhysicalMaterial({ color: 0x3a0203, roughness: 0.66, sheen: 0.25, sheenColor: new THREE.Color(0x802020) })),
        cloth: keep(new THREE.MeshPhysicalMaterial({ map: tex(ct.albedo, true, [1, 1]), normalMap: tex(ct.normal, false, [1, 1]), normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.9, sheen: 0.5, sheenRoughness: 0.7, sheenColor: new THREE.Color(0x8aa0c0) })),
        zoneTeal: keep(new THREE.MeshBasicMaterial({ map: tex(zoneTex(), false), color: 0x0fd4c4, transparent: true, opacity: 0.8, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4, side: THREE.DoubleSide })),
        zoneTeal2: keep(new THREE.MeshBasicMaterial({ map: tex(zoneTex(), false), color: 0x0fd4c4, transparent: true, opacity: 0.45, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4, side: THREE.DoubleSide })),
        zoneRed: keep(new THREE.MeshBasicMaterial({ map: tex(zoneTex(), false), color: 0xe5484d, transparent: true, opacity: 0.75, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4, side: THREE.DoubleSide })),
        contact: keep(new THREE.MeshBasicMaterial({ color: 0x000000, alphaMap: tex(contactTex(), false), transparent: true, opacity: 0.4, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })),
        guide: keep(new THREE.MeshBasicMaterial({ map: tex(guideTex(), false), color: 0x0fd4c4, transparent: true, opacity: 0.85, depthWrite: false, toneMapped: false, side: THREE.DoubleSide })),
        penBody: keep(new THREE.MeshPhysicalMaterial({ color: 0xeceef0, roughness: 0.35, clearcoat: 0.5 })),
        penCap: keep(new THREE.MeshPhysicalMaterial({ color: 0x250d8a, roughness: 0.4, clearcoat: 0.4 })),
        penTip: keep(new THREE.MeshStandardMaterial({ color: 0x030305, roughness: 0.9 })),
      };
      M.tex = tex;
      // the cloth texture tiles every 5 cm round and along the limb (uv in metres / 0.05 below)
      return M;
    }

    /* ─────────────── the wound (kind from the data) ─────────────── */
    makeWound() {
      const S = this.S, inj = this.d.injury, R = this.R, sev = this.sev;
      const c = this.wUv, seed = hash(inj.id || 'w') % 100000;
      const type = inj.type || 'gunshot';
      this.wST = S.uvToST(c);
      this.extra = [];
      let w;
      if (type === 'gunshot' || type === 'shrapnel') {
        const gun = type === 'gunshot';
        const rad = gun ? (2.8 + sev * 0.55) : (2.2 + sev * 0.45);
        w = S.wounds.add({ type: 'gunshot', uv: c, radius: rad * MM, ring: (gun ? 1.1 + sev * 0.22 : 0.7) * MM, depth: 12 * MM, jagged: gun ? 0.3 + sev * 0.08 : 0.85, seed });
        if (!gun) {
          for (let k = 0; k < 2 + Math.min(3, sev); k++) {
            const a = R() * TAU, dd = (9 + R() * 16) * MM;
            this.extra.push(S.wounds.add({ type: 'gunshot', uv: S.stToUv(this.wST[0] + Math.cos(a) * dd, this.wST[1] + Math.sin(a) * dd), radius: (0.7 + R() * 0.8) * MM, ring: 0.4 * MM, depth: 3 * MM, jagged: 0.9, seed: seed + 11 + k }));
          }
        }
        this.wRad = rad * MM;
      } else if (type === 'stab') {
        const L = clamp(num(inj.length, 0) || (14 + sev * 5), 12, 40);
        w = S.wounds.add({ type: 'stab', uv: c, angle: (R() - 0.5) * 0.6 + 0.25, length: L * MM, gape: (2.6 + sev * 0.5) * MM, depth: 12 * MM, jagged: 0.12, seed });
        this.wRad = L * MM / 2;
      } else {
        const L = clamp(num(inj.length, 0) || 45, 20, 110);
        w = S.wounds.add({ type: 'laceration', uv: c, angle: (R() - 0.5) * 0.35, length: L * MM, gape: clamp(L * 0.075, 3, 8) * MM, depth: clamp(5 + sev * 2, 5, 14) * MM, jagged: clamp(0.45 + sev * 0.08, 0.3, 0.8), seed });
        this.wRad = L * MM / 2;
      }
      this.w = w;
      this.extra.forEach(e => S.fluids.bleed(e, 0.8));
    }
    // a fresh field wound: blood in and around it, a bruise, smears running toward the ground, flecks
    paintInitial() {
      const S = this.S, R = this.R, sev = this.sev;
      const at = (ds, dt) => S.stToUv(this.wST[0] + ds, this.wST[1] + dt);
      for (let k = 0; k < 6; k++) {
        const a = R() * TAU, dd = (4 + R() * 12) * MM;
        S.layers.paint('bruise', at(Math.cos(a) * dd, Math.sin(a) * dd), [(10 + R() * 10) * MM, (7 + R() * 6) * MM], 0.05 + sev * 0.016, { hardness: 0, grain: 0.3, grainScale: 90, angle: R() * Math.PI });
      }
      S.layers.splat('blood', this.wUv, (2 + R() * 1.6) * MM, 0.7, { seed: 3, count: 6 });
      const reach = this.wRad + 6 * MM;
      for (let k = 0; k < 10 + sev * 3; k++) {
        const a = R() * TAU, dd = reach * (0.3 + R() * 1.2), down = R() * R() * 14 * MM;
        S.layers.splat('blood', at(Math.cos(a) * dd, Math.sin(a) * dd * 0.7 + down), (0.9 + R() * 1.8) * MM, 0.12 + R() * 0.22, { seed: 50 + k, count: 4 });
      }
      for (let k = 0; k < 30 + sev * 10; k++) {
        const a = R() * TAU, dd = reach + R() * R() * 26 * MM, r = (0.12 + R() * R() * 0.5) * MM;
        S.layers.paint('clot', at(Math.cos(a) * dd, Math.sin(a) * dd), [r * (0.8 + R() * 0.6), r], 0.18 + R() * 0.3, { hardness: 0.45, angle: R() * Math.PI });
      }
      for (let k = 0; k < 3; k++) {
        const s0 = (R() - 0.5) * this.wRad * 1.6, len = (12 + R() * 18) * MM;
        S.layers.stroke('clot', at(s0, this.wRad * 0.6), at(s0 + (R() - 0.5) * 6 * MM, this.wRad + len), 0.0008, 0.06, { hardness: 0.45, grain: 0.4, grainScale: 120 });
      }
      for (let k = 0; k < 2; k++) S.fluids.drip(at((R() - 0.5) * this.wRad, this.wRad + 1 * MM), 0.1 + R() * 0.05);
    }

    /* ─────────────── clothing over the rest of the limb ─────────────── */
    makeClothing() {
      const S = this.S, Rs = this.Rs;
      const s0 = this.sCov - 0.003, s1 = this.W / 2 + 0.4;
      const NA = 96, NL = 44, R2 = rng(this.seed + 5);
      const folds = Array.from({ length: 6 }, () => ({ f: 18 + R2() * 40, p: R2() * TAU, k: 2 + Math.floor(R2() * 4), amp: 0.0003 + R2() * 0.0006 }));
      const g = this.keep(gridGeo(NA, NL));
      const pos = g.attributes.position.array, uv = g.attributes.uv.array, out = new Float32Array((NA + 1) * (NL + 1) * 3);
      for (let j = 0; j <= NL; j++) {
        const s = lerp(s0, s1, Math.pow((NL - j) / NL, 1.6));   // far end first: front faces point outward
        const dc = s - this.sCov;
        for (let i = 0; i <= NA; i++) {
          const a = (i / NA) * TAU - Math.PI, k = j * (NA + 1) + i;
          let r = this.clothR(Math.max(s, this.sCov));
          // creases: rings bunched near the hem / roll, a few long folds along the limb
          let f = 0;
          folds.forEach(o => { f += o.amp * Math.sin(dc * o.f + Math.sin(a * o.k + o.p) * 1.4 + o.p); });
          f += 0.0011 * Math.sin(dc * 160 + Math.sin(a * 3) * 2) * Math.exp(-dc / 0.05);
          r += Math.max(-0.0025, f + 0.0006 * Math.sin(a * 5 + dc * 20));   // never down to the skin
          pos[k * 3] = s; pos[k * 3 + 1] = r * Math.cos(a) - Rs; pos[k * 3 + 2] = r * Math.sin(a);
          out[k * 3] = 0; out[k * 3 + 1] = Math.cos(a); out[k * 3 + 2] = Math.sin(a);
          uv[k * 2] = s / 0.05; uv[k * 2 + 1] = (a * r) / 0.05;
        }
      }
      g.attributes.uv.needsUpdate = true;
      gridNormals(g, NA, NL, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
      const mesh = new THREE.Mesh(g, this.M.cloth);
      mesh.receiveShadow = true; mesh.castShadow = true; mesh.frustumCulled = false;
      S.scene.add(mesh);
      // the cut / rolled edge: a soft roll of cloth with a frayed look
      const lowerW = this.lowerWound, tube = lowerW ? 0.0095 : 0.0055;
      const rr = this.clothR(this.sCov) + (lowerW ? 0.002 : 0.0008);
      const tg = this.keep(new THREE.TorusGeometry(rr, tube, 16, 120));
      {
        // a roll of fabric: lumpy, a little flattened onto the limb, thicker in places
        const p = tg.attributes.position;
        for (let i = 0; i < p.count; i++) {
          const x = p.getX(i), y = p.getY(i), z = p.getZ(i), a = Math.atan2(y, x), rc = Math.hypot(x, y);
          const w = 1 + 0.1 * Math.sin(a * 5 + 1.3) + 0.06 * Math.sin(a * 11 + 0.4) + 0.03 * Math.sin(a * 23);
          const off = (rc - rr) * w;
          p.setXYZ(i, Math.cos(a) * (rr + off), Math.sin(a) * (rr + off), z * w * 1.25);
        }
        tg.computeVertexNormals();
      }
      tg.rotateY(Math.PI / 2);
      const roll = new THREE.Mesh(tg, this.M.cloth);
      roll.position.set(this.sCov + tube * 0.8, -Rs, 0); roll.castShadow = true; roll.receiveShadow = true;
      S.scene.add(roll);
      this.clothMesh = mesh; this.rollMesh = roll;
    }

    /* ─────────────── bands round the limb: where the strap goes (teal) and the joint (red) ─────────────── */
    zoneStrip(t0, t1, mat) {
      const S = this.S, Rs = this.Rs, NA = 120, NL = 3;
      const sA = this.sOf(Math.max(t0, t1)), sB = this.sOf(Math.min(t0, t1));
      const g = this.keep(gridGeo(NA, NL)), pos = g.attributes.position.array, out = new Float32Array((NA + 1) * (NL + 1) * 3), uv = g.attributes.uv.array;
      for (let j = 0; j <= NL; j++) {
        const s = lerp(sA, sB, j / NL);
        const r = this.baseR(s) + (this.onCloth(s) ? 0.0026 : 0.0007);
        for (let i = 0; i <= NA; i++) {
          const a = (i / NA) * TAU - Math.PI, k = j * (NA + 1) + i;
          pos[k * 3] = s; pos[k * 3 + 1] = r * Math.cos(a) - Rs; pos[k * 3 + 2] = r * Math.sin(a);
          out[k * 3] = 0; out[k * 3 + 1] = Math.cos(a); out[k * 3 + 2] = Math.sin(a);
          uv[k * 2] = (a * r) / 0.06; uv[k * 2 + 1] = j / NL;
        }
      }
      g.attributes.uv.needsUpdate = true;
      gridNormals(g, NA, NL, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
      const m = new THREE.Mesh(g, mat);
      m.renderOrder = 4; m.frustumCulled = false; m.visible = false;
      this.S.scene.add(m);
      return m;
    }
    makeZones() {
      const tune = this.tune, tj = this.tj, jz = this.jz;
      this.zones = [];
      const jA = tj * (1 - jz), jB = tj + (1 - tj) * jz;
      this.jointT = [jA, jB];
      if (this.lowerWound || !this.d.injury) this.zones.push({ id: 'joint', mesh: this.zoneStrip(jA, jB, this.M.zoneRed), t: (jA + jB) / 2 });
      // high and tight: the top third of the upper arm / thigh
      const hA = this.tMin, hB = this.d.injury ? Math.min(0.35 * tj, this.tw - 1.5 / tune.length) : 0.35 * tj;
      // 5–8 cm above the wound (not on the joint, not past the root)
      if (this.d.injury) {
        let a = this.tw - tune.idealAbove[1] / tune.length, b = this.tw - tune.idealAbove[0] / tune.length;
        a = Math.max(a, this.tMin); b = Math.min(b, this.tMax);
        if (b > jA && a < jB) { if (a < jA) b = jA; else a = jB; }
        if (b - a > 0.004 && !(a < hB && b <= hB)) this.zones.push({ id: 'ideal', mesh: this.zoneStrip(a, b, this.M.zoneTeal), t: (a + b) / 2 });
      }
      this.zoneEnd = { high: hB - 0.02 };
      if (hB - hA > 0.004) this.zones.push({ id: 'high', mesh: this.zoneStrip(hA, hB, this.d.injury ? this.M.zoneTeal2 : this.M.zoneTeal), t: (hA + hB) / 2 });
    }
    showZones(on) { (this.zones || []).forEach(z => { z.mesh.visible = on; }); }

    /* ─────────────── the tourniquet ─────────────── */
    makeTq() {
      const S = this.S, M = this.M, keep = x => this.keep(x);
      const tq = this.tq = {};
      const NA = 150;
      tq.NA = NA;
      tq.band = new THREE.Mesh(keep(loopTubeGeo(NA)), M.band);
      tq.band.castShadow = true; tq.band.receiveShadow = true; tq.band.frustumCulled = false;
      S.scene.add(tq.band);
      // contact shadow on the skin round the band (dark where it presses, fades out)
      tq.cg = keep(gridGeo(110, 1));
      tq.contact = new THREE.Mesh(tq.cg, M.contact);
      tq.contact.renderOrder = 3; tq.contact.frustumCulled = false; tq.contact.visible = false;
      S.scene.add(tq.contact);
      // windlass plate (curved to the band), hub, the clip hooks, the windlass strap with the TIME label
      const plate = tq.plate = new THREE.Group();
      const shape = new THREE.Shape();
      const rr = 0.006, hx = PLX, hz = PLZ;
      shape.moveTo(-hx + rr, -hz); shape.lineTo(hx - rr, -hz); shape.quadraticCurveTo(hx, -hz, hx, -hz + rr); shape.lineTo(hx, hz - rr); shape.quadraticCurveTo(hx, hz, hx - rr, hz);
      shape.lineTo(-hx + rr, hz); shape.quadraticCurveTo(-hx, hz, -hx, hz - rr); shape.lineTo(-hx, -hz + rr); shape.quadraticCurveTo(-hx, -hz, -hx + rr, -hz);
      const pg = keep(new THREE.ExtrudeGeometry(shape, { depth: PLY - 0.0012, bevelEnabled: true, bevelThickness: 0.0006, bevelSize: 0.0012, bevelSegments: 2, curveSegments: 6 }));
      pg.rotateX(-Math.PI / 2);     // extrusion (+z) → +y; shape y → -z
      pg.translate(0, 0.0006, 0);
      tq.plateGeo = pg;
      tq.plateMesh = new THREE.Mesh(pg, M.plastic);
      plate.add(tq.plateMesh);
      // raised ribs on the plate (molded grip) and the hub the rod turns on
      for (const x of [-0.021, -0.0165, 0.0165, 0.021]) { const rb = new THREE.Mesh(keep(new THREE.BoxGeometry(0.0018, 0.001, PLZ * 1.4)), M.plastic); rb.position.set(x, PLY + 0.0004, 0); plate.add(rb); }
      const hub = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.0075, 0.0085, 0.003, 24)), M.plastic);
      hub.position.set(0, PLY + 0.0016, 0); plate.add(hub);
      // the twisted inner band between the plate and the rod (grows as it winds)
      tq.bundle = new THREE.Mesh(keep(new THREE.CylinderGeometry(1, 1.15, 1, 18, 1, true)), M.band);
      tq.bundle.position.set(0, PLY, 0); plate.add(tq.bundle);
      // C-hooks of the clip, open upward, the rod drops into them along the limb axis
      const hookGeo = keep(new THREE.TorusGeometry(HOOK_R, HOOK_T, 8, 28, TAU - HOOK_GAP));
      hookGeo.rotateZ(Math.PI / 2 - (TAU - HOOK_GAP / 2));
      hookGeo.rotateY(Math.PI / 2);
      tq.hooks = [];
      for (const sx of [-1, 1]) {
        const hk = new THREE.Mesh(hookGeo, M.hook);
        hk.position.set(sx * HOOK_X, H_LOCK, 0); plate.add(hk);
        const post = new THREE.Mesh(keep(new THREE.BoxGeometry(0.004, H_LOCK - HOOK_R - PLY + 0.0008, 0.006)), M.hook);
        post.position.set(sx * HOOK_X, PLY + (H_LOCK - HOOK_R - PLY) / 2, 0); plate.add(post);
        tq.hooks.push(hk);
      }
      // the rod (turns about the plate normal; drops into the hooks when locked)
      tq.rodPivot = new THREE.Group(); tq.rodPivot.position.set(0, H_TURN, 0); plate.add(tq.rodPivot);
      const rodG = keep(new THREE.CapsuleGeometry(ROD_R, ROD_L - ROD_R * 2, 6, 18)); rodG.rotateZ(Math.PI / 2);
      tq.rodPivot.add(new THREE.Mesh(rodG, M.rod));
      for (const x of [-0.036, -0.031, -0.026, 0.026, 0.031, 0.036]) {
        const ring = new THREE.Mesh(keep(new THREE.TorusGeometry(ROD_R + 0.0002, 0.0005, 6, 20)), M.grip);
        ring.rotation.y = Math.PI / 2; ring.position.x = x; tq.rodPivot.add(ring);
      }
      // turning guide (dashed circle, arrows) in the rod's plane
      tq.guide = new THREE.Mesh(keep(new THREE.PlaneGeometry(ROD_L * 1.32, ROD_L * 1.32)), M.guide);
      tq.guide.rotation.x = -Math.PI / 2; tq.guide.position.y = H_TURN + 0.0008; tq.guide.renderOrder = 6; tq.guide.visible = false;
      plate.add(tq.guide);
      // windlass strap: a short webbing strap hinged beyond the +x hook. Open it bends down and lies on
      // the skin; closed it folds back over the rod in the clip and carries the TIME label on top
      tq.strapLen = 2 * HOOK_X + 0.02;
      tq.strapHinge = [HOOK_X + 0.008, H_LOCK + ROD_R + 0.0014];
      tq.sg = keep(gridGeo(1, 20));
      { const uv = tq.sg.attributes.uv.array; for (let j = 0; j <= 20; j++) for (let i = 0; i <= 1; i++) { const k = j * 2 + i; uv[k * 2] = (j / 20) * tq.strapLen / 0.04; uv[k * 2 + 1] = 0.12 + i * 0.76; } }
      tq.strap = new THREE.Mesh(tq.sg, M.tail);
      tq.strap.frustumCulled = false;
      plate.add(tq.strap);
      this.labelCv = cvs(512, 205);
      tq.labelTex = M.tex(this.labelCv, true); tq.labelTex.wrapS = tq.labelTex.wrapT = THREE.ClampToEdgeWrapping;
      tq.label = new THREE.Mesh(keep(new THREE.PlaneGeometry(0.05, 0.02)), keep(new THREE.MeshStandardMaterial({ map: tq.labelTex, roughness: 0.82, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })));
      plate.add(tq.label);
      this.drawLabel();
      plate.traverse(o => { if (o.isMesh) { o.castShadow = o !== tq.guide && o !== tq.label; o.receiveShadow = true; } });
      S.scene.add(plate);
      // buckle (friction adapter): a frame with two slots on the near side
      const buckle = tq.buckle = new THREE.Group();
      const bar = (w, d, x, z) => { const m = new THREE.Mesh(keep(new THREE.BoxGeometry(w, 0.0032, d)), M.buckle); m.position.set(x, 0.0016, z); buckle.add(m); };
      bar(BW + 0.009, 0.0034, 0, -0.0085); bar(BW + 0.009, 0.0034, 0, 0.0085); bar(BW + 0.009, 0.0028, 0, 0);
      bar(0.0038, 0.02, -(BW / 2 + 0.0026), 0); bar(0.0038, 0.02, BW / 2 + 0.0026, 0);
      buckle.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      S.scene.add(buckle);
      // free end (running end) with the red pull tab
      tq.NT = 28;
      tq.tg = keep(gridGeo(2, tq.NT));
      tq.tail = new THREE.Mesh(tq.tg, M.tail);
      tq.tail.castShadow = true; tq.tail.receiveShadow = true; tq.tail.frustumCulled = false;
      S.scene.add(tq.tail);
      tq.tab = new THREE.Mesh(keep(new THREE.BoxGeometry(BW * 0.62, 0.0026, 0.017)), M.tab);
      tq.tab.castShadow = true;
      S.scene.add(tq.tab);
      // loop state
      this.lp = { s: this.sOf(this.tIdeal()), k: 0, loose: 1, sink: 0, free: null, mode: 'rest', tail: 'pull', tailK: 0, pull: 0, fold: 0, drop: 0 };
      this.restPose();
      this.lp.free = this.lp.rest.clone();
      this.poseTq(0, true);
    }
    // where the strap waits: on the far side of the limb, on the blanket, beside the strap zone
    restPose() {
      const Rs = this.Rs, s = clamp(this.sOf(this.tIdeal()) + 0.02, -this.W / 2 + 0.12, this.W / 2 - 0.12);
      const z = -(Rs * 1.1 + (this.kind === 'arm' ? 0.082 : 0.112));
      let y = this.clothY;
      const cl = this.S._cloth;
      if (cl) {
        cl.updateMatrixWorld(true);
        this.rc.ray.origin.set(s, 0.5, z); this.rc.ray.direction.set(0, -1, 0);
        const h = this.rc.intersectObject(cl, false)[0];
        if (h) y = h.point.y;
      }
      this.lp.rest = V3(s, y + 0.0035 + TH / 2 + 0.0012, z);
      this.lp.restY = y;
    }
    // loop shapes: { C, U (a = 0), V (a = π/2), A (across), rx, ry, ph }
    shapeFlat(C) { return { C, U: V3(1, 0, 0), V: V3(0, 1, 0), A: V3(0, 0, 1), rx: 0.082, ry: 0.0035, ph: Math.PI / 2 - A_W }; }
    shapeOn(s, loose, sink) {
      const rb = this.baseR(s) + TH / 2 - sink;
      const Rl = rb + 0.03 * loose;
      return { C: V3(s, -this.Rs - (Rl - rb), 0), U: V3(0, 1, 0), V: V3(0, 0, 1), A: V3(1, 0, 0), rx: Rl, ry: Rl, ph: 0 };
    }
    // point + frame on a shape at loop angle a: p (centre line), n (out), w (across)
    static shapeAt(sh, a, out) {
      const b = a + sh.ph, c = Math.cos(b), s = Math.sin(b);
      out.p.copy(sh.C).addScaledVector(sh.U, sh.rx * c).addScaledVector(sh.V, sh.ry * s);
      out.n.set(0, 0, 0).addScaledVector(sh.U, c * sh.ry).addScaledVector(sh.V, s * sh.rx).normalize();
      out.w.copy(sh.A);
      return out;
    }
    // the blended frame (flat ↔ on the limb) at loop angle a
    frameAt(a, out) {
      const k = this.lp.k, f1 = this._f1 || (this._f1 = { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0) }), f2 = this._f2 || (this._f2 = { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0) });
      Game.shapeAt(this.shA, a, f1); Game.shapeAt(this.shB, a, f2);
      out = out || { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0), t: V3(0, 0, 0) };
      out.p.copy(f1.p).lerp(f2.p, k);
      out.n.copy(f1.n).lerp(f2.n, k).normalize();
      out.w.copy(f1.w).lerp(f2.w, k).normalize();
      out.t = out.t || V3(0, 0, 0);
      out.t.crossVectors(out.w, out.n).normalize();
      out.n.crossVectors(out.t, out.w).normalize();
      return out;
    }
    // rebuild the band, place the hardware and the free end (dt: animation step)
    poseTq(dt, force) {
      const lp = this.lp, tq = this.tq;
      this.shA = this.shapeFlat(lp.free);
      this.shB = this.shapeOn(lp.s, lp.loose, lp.sink);
      const key = `${lp.k.toFixed(4)}|${lp.s.toFixed(5)}|${lp.loose.toFixed(4)}|${lp.sink.toFixed(5)}|${lp.free.x.toFixed(5)},${lp.free.y.toFixed(5)},${lp.free.z.toFixed(5)}`;
      if (force || key !== tq.key) {
        tq.key = key;
        this.buildBand();
        this.buildContact();
      }
      // hardware
      const F = this.frameAt(A_W, this._fw);
      this._fw = F;
      const P = tq.plate;
      P.position.copy(F.p).addScaledVector(F.n, TH / 2 - 0.0002);
      const m = this._m || (this._m = new THREE.Matrix4());
      m.makeBasis(F.w, F.n, F.t); P.quaternion.setFromRotationMatrix(m);
      const q = this.q;
      tq.rodPivot.position.y = lerp(H_TURN, H_LOCK, lp.drop);
      tq.rodPivot.rotation.y = q.theta - Math.PI / 2;
      // inner band bunching under the rod: thicker the more it is wound
      const turns = Math.abs(q.theta) / TAU;
      const hb = Math.max(0.001, tq.rodPivot.position.y - PLY);
      tq.bundle.scale.set(0.0058 + Math.min(0.004, turns * 0.0014), hb, 0.0058 + Math.min(0.004, turns * 0.0014));
      tq.bundle.position.y = PLY + hb / 2;
      tq.bundle.rotation.y = q.theta;
      if (tq.foldAt !== lp.fold) { tq.foldAt = lp.fold; this.bendStrap(lp.fold); }
      const B = this.frameAt(A_B, this._fb);
      this._fb = B;
      tq.buckle.position.copy(B.p).addScaledVector(B.n, TH / 2);
      m.makeBasis(B.w, B.n, B.t); tq.buckle.quaternion.setFromRotationMatrix(m);
      this.buildTail(B);
    }
    // the windlass strap's centre line in the plate's x–y plane for a fold 0 (open, on the skin) … 1 (closed)
    bendStrap(f) {
      const tq = this.tq, g = tq.sg, pos = g.attributes.position.array, out = new Float32Array(2 * 21 * 3), N = 20;
      const LS = tq.strapLen, hx = tq.strapHinge[0], hy = tq.strapHinge[1], half = 0.012;
      // open: eases down off the hinge onto the skin (just above it), then lies flat toward the root
      const yFlat = -0.0007, dx = 0.013, drop = hy - yFlat;
      const ph = f * Math.PI, c = Math.cos(ph), sn = Math.sin(ph), k2 = f * f;
      const pts = [];
      for (let j = 0; j <= N; j++) {
        const u = (j / N) * LS;
        const ox = u, oy = u < dx ? -drop * (0.5 - 0.5 * Math.cos(Math.PI * u / dx)) : -drop;
        // swing over the hinge (rotation by f·π in the x–y plane), ending straight back over the rod
        const rx = ox * c - oy * sn, ry = ox * sn + oy * c;
        pts.push([hx + lerp(rx, -u, k2), hy + lerp(ry, 0, k2)]);
      }
      const hint = [-sn, c];
      for (let j = 0; j <= N; j++) {
        for (let i = 0; i <= 1; i++) {
          const k = j * 2 + i;
          pos[k * 3] = pts[j][0]; pos[k * 3 + 1] = pts[j][1]; pos[k * 3 + 2] = i ? -half : half;   // front face = top when open
          out[k * 3] = hint[0]; out[k * 3 + 1] = hint[1]; out[k * 3 + 2] = 0;
        }
      }
      gridNormals(g, 1, N, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
      // the label: middle of the strap's long part, on the face that is up once it is closed
      const jm = Math.round(N * 0.62), a = pts[jm - 1], b = pts[jm + 1], m = pts[jm];
      const dl = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, d = [(b[0] - a[0]) / dl, (b[1] - a[1]) / dl], n = [d[1], -d[0]];
      const L = tq.label, X = V3(-d[0], -d[1], 0), Z = V3(n[0], n[1], 0), Y = V3(0, 0, 0).crossVectors(Z, X);
      L.position.set(m[0] + n[0] * 0.0009, m[1] + n[1] * 0.0009, 0);
      const mm = this._m3 || (this._m3 = new THREE.Matrix4());
      mm.makeBasis(X, Y, Z); L.quaternion.setFromRotationMatrix(mm);
      L.visible = f > 0.55;
    }
    buildBand() {
      const tq = this.tq, NA = tq.NA, g = tq.band.geometry, pos = g.attributes.position.array, nor = g.attributes.normal.array, uv = g.attributes.uv.array;
      const k = this.lp.k, A = this.shA, B = this.shB;
      const f1 = { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0) }, f2 = { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0) };
      const P = V3(0, 0, 0), N = V3(0, 0, 0), Wv = V3(0, 0, 0), Tm = V3(0, 0, 0);
      // perimeter (for the texture scale): an integer number of tiles so the seam (underneath) matches
      const per = lerp(TAU * Math.sqrt((A.rx * A.rx + A.ry * A.ry) / 2), TAU * B.rx, k);
      const tiles = Math.max(1, Math.round(per / 0.04));
      const a0 = A_W + Math.PI;     // the seam sits underneath
      // twist bunching: the band gathers toward the windlass as it is wound
      const wind = clamp(Math.abs(this.q.theta) / TAU, 0, 4) * (1 - this.lp.loose);
      for (let j = 0; j < NA; j++) {
        const a = a0 + (j / NA) * TAU;
        Game.shapeAt(A, a, f1); Game.shapeAt(B, a, f2);
        P.copy(f1.p).lerp(f2.p, k); N.copy(f1.n).lerp(f2.n, k).normalize(); Wv.copy(f1.w).lerp(f2.w, k).normalize();
        Tm.crossVectors(Wv, N); N.crossVectors(Tm.normalize(), Wv).normalize();
        const da = angDiff(a, A_W);
        const gather = wind * 0.0006 * Math.exp(-da * da / 0.05) * Math.sin(da * 60);
        for (let i = 0; i < NP; i++) {
          const pr = PROF[i], kk = j * NP + i;
          const x = pr.x * (1 - 0.06 * wind * Math.exp(-da * da / 0.04)), h = pr.h + gather * (pr.h > 0 ? 1 : 0);
          pos[kk * 3] = P.x + N.x * h + Wv.x * x; pos[kk * 3 + 1] = P.y + N.y * h + Wv.y * x; pos[kk * 3 + 2] = P.z + N.z * h + Wv.z * x;
          nor[kk * 3] = N.x * pr.nh + Wv.x * pr.nx; nor[kk * 3 + 1] = N.y * pr.nh + Wv.y * pr.nx; nor[kk * 3 + 2] = N.z * pr.nh + Wv.z * pr.nx;
          uv[kk * 2] = (j / NA) * tiles; uv[kk * 2 + 1] = pr.v;
        }
      }
      g.attributes.position.needsUpdate = true; g.attributes.normal.needsUpdate = true; g.attributes.uv.needsUpdate = true;
      g.computeBoundingSphere();
    }
    // contact shadow strip on the skin / cloth under and beside the band (only on the limb)
    buildContact() {
      const tq = this.tq, lp = this.lp, on = lp.k > 0.85;
      tq.contact.visible = on && tq.band.visible;
      if (!on) return;
      const g = tq.cg, NA = 110, pos = g.attributes.position.array, out = new Float32Array((NA + 1) * 2 * 3), uv = g.attributes.uv.array;
      const s = lp.s, r = this.baseR(s) + (this.onCloth(s) ? 0.0024 : 0.0005), Rs = this.Rs, half = BW / 2 + 0.013;
      for (let j = 0; j <= 1; j++) {
        for (let i = 0; i <= NA; i++) {
          const a = (i / NA) * TAU - Math.PI, k = j * (NA + 1) + i;
          pos[k * 3] = s + (j ? half : -half); pos[k * 3 + 1] = r * Math.cos(a) - Rs; pos[k * 3 + 2] = r * Math.sin(a);
          out[k * 3] = 0; out[k * 3 + 1] = Math.cos(a); out[k * 3 + 2] = Math.sin(a);
          uv[k * 2] = 0.5; uv[k * 2 + 1] = j;
        }
      }
      g.attributes.uv.needsUpdate = true;
      gridNormals(g, NA, 1, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
      this.M.contact.opacity = lerp(0.28, 0.62, clamp(1 - lp.loose, 0, 1) * (0.55 + 0.45 * clamp(this.q.P / this.tune.occlusion, 0, 1.2)));
    }
    // the free end: hanging off the buckle, pulled out, or fastened back over the band
    tailPath(state, B, out) {
      const lp = this.lp, NT = this.tq.NT;
      const start = B.p.clone().addScaledVector(B.n, TH * 1.1);
      if (state === 'fast') {
        // round the limb on top of the band from the buckle (only on the limb)
        const sh = this.shB, f = { p: V3(0, 0, 0), n: V3(0, 0, 0), w: V3(0, 0, 0) };
        for (let i = 0; i <= NT; i++) {
          const a = A_B + 0.05 + (i / NT) * 1.9;
          Game.shapeAt(sh, a, f);
          out[i] = f.p.clone().addScaledVector(f.n, TH * 1.25 + 0.0003);
        }
        return out;
      }
      if (state === 'pull') {
        const dir = B.t.clone().addScaledVector(B.n, 0.22 * lp.k).normalize();
        // the tab stays under the cursor: the pull is measured on screen (SLACK_PX of the screen per full pull)
        let L = 0.03;
        if (lp.pull > 0 && this.S) {
          const a = this.S.project(start), b = this.S.project(start.clone().addScaledVector(dir, 0.05));
          const px = Math.hypot((b.x - a.x) * window.innerWidth, (b.y - a.y) * window.innerHeight) || 1;
          L += lp.pull * SLACK_PX * window.innerHeight * (0.05 / px);
        }
        for (let i = 0; i <= NT; i++) { const u = i / NT; out[i] = start.clone().addScaledVector(B.t, Math.min(u * L, 0.008)).addScaledVector(dir, Math.max(0, u * L - 0.008)); }
        return out;
      }
      // hanging: out along the band a little, then down to the blanket (lying on it)
      const L = 0.13, floor = (lp.restY !== undefined ? lp.restY : this.clothY) + 0.0016;
      const down = V3(0, -1, 0);
      const p = start.clone(), d = B.t.clone();
      out[0] = p.clone();
      for (let i = 1; i <= NT; i++) {
        const step = L / NT;
        d.lerp(down, 0.11).normalize();
        p.addScaledVector(d, step);
        if (p.y < floor) { p.y = floor; d.y = 0; if (d.lengthSq() < 1e-6) d.copy(B.t).setY(0); d.normalize(); }
        out[i] = p.clone();
      }
      return out;
    }
    buildTail(B) {
      const tq = this.tq, lp = this.lp, NT = tq.NT;
      this._ta = this._ta || []; this._tb = this._tb || [];
      let pts;
      if (lp.tail === 'fast' && lp.tailK < 1) {
        const a = this.tailPath('pull', B, this._ta), b = this.tailPath('fast', B, this._tb), k = smooth(0, 1, lp.tailK);
        pts = a.map((p, i) => p.clone().lerp(b[i], k));
      } else pts = this.tailPath(lp.tail, B, this._ta);
      const g = tq.tg, pos = g.attributes.position.array, out = new Float32Array(3 * 3 * (NT + 1));
      const Wv = B.w, half = BW * 0.47;
      for (let j = 0; j <= NT; j++) {
        const p = pts[j], pn = pts[Math.min(NT, j + 1)], pp = pts[Math.max(0, j - 1)];
        const tg = pn.clone().sub(pp).normalize();
        const nrm = V3(0, 0, 0).crossVectors(tg, Wv).normalize();   // outward = the strip's front face
        for (let i = 0; i <= 2; i++) {
          const x = (i / 2 - 0.5) * 2 * half, k = j * 3 + i;
          pos[k * 3] = p.x + Wv.x * x; pos[k * 3 + 1] = p.y + Wv.y * x; pos[k * 3 + 2] = p.z + Wv.z * x;
          out[k * 3] = nrm.x; out[k * 3 + 1] = nrm.y; out[k * 3 + 2] = nrm.z;
        }
      }
      const uv = g.attributes.uv.array;
      for (let j = 0; j <= NT; j++) for (let i = 0; i <= 2; i++) { const k = j * 3 + i; uv[k * 2] = (j / NT) * 4; uv[k * 2 + 1] = i / 2; }
      g.attributes.uv.needsUpdate = true;
      gridNormals(g, 2, NT, k => [out[k * 3], out[k * 3 + 1], out[k * 3 + 2]]);
      // red pull tab at the end
      const e = pts[NT], e0 = pts[NT - 1], tdir = e.clone().sub(e0).normalize();
      const nrm = V3(0, 0, 0).crossVectors(tdir, Wv).normalize();
      tq.tab.position.copy(e).addScaledVector(tdir, 0.0075).addScaledVector(nrm, 0.0008);
      const m = this._m2 || (this._m2 = new THREE.Matrix4());
      m.makeBasis(Wv, nrm, V3(0, 0, 0).crossVectors(Wv, nrm).normalize());
      tq.tab.quaternion.setFromRotationMatrix(m);
      tq.tabEnd = e.clone();
      tq.tabDir = tdir;
    }
    // TIME label (white, red header, the time in marker revealed as it is written)
    drawLabel() {
      const c = this.labelCv, x = c.getContext('2d'), W = c.width, H = c.height, q = this.q;
      x.clearRect(0, 0, W, H);
      x.fillStyle = '#f3f1ea'; x.fillRect(0, 0, W, H);
      const r = rng(31);
      for (let i = 0; i < 500; i++) { x.fillStyle = `rgba(120,110,95,${0.03 + r() * 0.05})`; x.fillRect(r() * W, r() * H, 1 + r() * 2, 1 + r() * 2); }
      x.strokeStyle = 'rgba(40,40,40,.35)'; x.lineWidth = 4; x.strokeRect(6, 6, W - 12, H - 12);
      x.fillStyle = '#c52a2a'; x.font = '800 40px Lexend, Arial, sans-serif'; x.textBaseline = 'alphabetic';
      x.fillText('TIME', 26, 58);
      x.fillRect(26, 70, 116, 5);
      x.strokeStyle = 'rgba(30,30,30,.45)'; x.lineWidth = 3;
      x.beginPath(); x.moveTo(170, H - 40); x.lineTo(W - 26, H - 40); x.stroke();
      const wr = clamp(q.written, 0, 1);
      if (wr > 0) {
        x.save();
        x.beginPath(); x.rect(160, 0, (W - 180) * wr, H); x.clip();
        x.fillStyle = '#13213b';
        x.font = 'italic 700 104px "Segoe Print","Bradley Hand","Comic Sans MS","Marker Felt",cursive';
        x.translate(186, H - 52); x.rotate(-0.035);
        x.fillText(q.time || '--:--', 0, 0);
        x.restore();
      }
      if (this.tq && this.tq.labelTex) this.tq.labelTex.needsUpdate = true;
    }

    /* ─────────────── the marker pen (time label) ─────────────── */
    makePen() {
      const M = this.M, keep = x => this.keep(x);
      const pen = this.pen = new THREE.Group();
      const add = (geo, mat, y) => { const m = new THREE.Mesh(keep(geo), mat); m.position.y = y; m.castShadow = true; pen.add(m); return m; };
      add(new THREE.ConeGeometry(0.0016, 0.005, 16), M.penTip, 0.0025).rotation.x = Math.PI;
      add(new THREE.CylinderGeometry(0.0028, 0.0038, 0.007, 20), M.penCap, 0.0085);
      add(new THREE.CylinderGeometry(0.0044, 0.0044, 0.06, 24), M.penBody, 0.042);
      add(new THREE.CylinderGeometry(0.0048, 0.0048, 0.02, 24), M.penCap, 0.082);
      add(new THREE.SphereGeometry(0.0048, 16, 10, 0, TAU, 0, Math.PI / 2), M.penCap, 0.092);
      add(new THREE.BoxGeometry(0.0013, 0.016, 0.003), M.penCap, 0.082).position.z = 0.005;
      pen.visible = false;
      this.S.scene.add(pen);
    }

    // compile every shader up front behind the loading veil (no hitch on the first use)
    prewarm() {
      const S = this.S, tq = this.tq, shown = [];
      const show = o => { if (o && !o.visible) { o.visible = true; shown.push(o); } };
      [tq.guide, tq.contact, this.pen].forEach(show);
      (this.zones || []).forEach(z => show(z.mesh));
      S.markers.set('__w', { uv: [0.02, 0.02], kind: 'dashed' });
      S.prewarm([], false);
      S.markers.remove('__w');
      shown.forEach(o => { o.visible = false; });
    }

    /* ─────────────── step flow ─────────────── */
    nextStep() {
      this.stepIdx += 1;
      const name = this.steps[this.stepIdx];
      if (!name) return this.finish();
      this.enter(name);
    }
    enter(name, opts) {
      if (this.ph && this.ph.exit) this.ph.exit();
      // a strap carry belongs to the place step: never let one outlive it (it would block P and draw the strap astray)
      this.carry = null; this.lp.sTarget = undefined;
      const make = { place: this.phPlace, slack: this.phSlack, twist: this.phTwist, lock: this.phLock }[name] || this.phPlace;
      this.ph = make.call(this, opts || {});
      this.ph.name = name;
      if (this.ph.t0 === undefined) this.ph.t0 = this.t;
      const names = [T('tq3_sn_place', 'Place it high and tight'), T('tq3_sn_slack', 'Pull the slack out'), T('sn_twist', 'Turn the windlass'), T('tq3_sn_lock', 'Lock it, mark the time')];
      const lbl = this.d.regionLabel || (this.d.injury && this.d.injury.regionLabel) || '';
      this.app.pp.set(Object.assign({
        step: this.stepIdx + 1, total: this.steps.length, tag: `${T('tag_tq', 'Tourniquet')} · ${lbl}`.replace(/ · $/, ''),
        steps: names, titleTone: '', hints: this.hintsFor(this.ph.hints),
      }, this.ph.panelInit()));
      this.updateTools();
      if (this.ph.panel) this.ph.panel();
    }
    hintsFor(own) {
      return (own || []).concat([
        { keys: [T('b3_k_rmb', 'RMB')], label: T('b3_h_look', 'Look around') },
        { keys: [T('b3_k_wheel', 'Wheel')], label: T('b3_h_zoom', 'Zoom') },
        { keys: ['R'], label: T('b3_h_recentre', 'Recentre') },
      ]);
    }
    toolIdx() { return this.stepIdx <= 1 ? 0 : this.stepIdx === 2 ? 1 : (this.q.locked ? 3 : 2); }
    updateTools() {
      const cur = this.finished ? 4 : this.toolIdx();
      const list = [
        { label: T('tool_strap', 'Strap'), sub: T('tq3_sub_strap', 'Band + buckle'), icon: 'tq-strap' },
        { label: T('tool_windlass', 'Windlass'), sub: T('tq3_sub_rod', 'Turn the rod'), icon: 'refresh' },
        { label: T('tool_clip', 'Clip'), sub: T('tq3_sub_clip', 'Rod lock'), icon: 'tq-clip' },
        { label: T('tq3_tool_marker', 'Marker'), sub: T('tq3_sub_marker', 'Time label'), icon: 'edit' },
      ];
      this.app.pp.set({
        tools: list.map((t, i) => Object.assign(t, {
          key: String(i + 1), state: i < cur ? 'done' : i === cur ? 'active' : 'locked',
          why: T('b3_tool_later', 'Finish the step you are on first.'),
        })),
      });
    }
    pickTool(key) {
      const i = (+key || 0) - 1, cur = this.toolIdx();
      if (!this.ph || this.finished || i === cur || i < 0 || i > 3) return;
      if (i < cur) this.app.pp.flash('warn', T('b3_tool_done', 'That step is done.'), 1600);
    }
    stepDone(flash, ms) {
      const ph = this.ph;
      if (!ph || ph.finished) return;
      ph.finished = true;
      NZA.audio.success();
      if (flash) this.app.pp.flash('ok', flash, ms || 1800);
      this.cursor(null, '');
      const name = ph.name;
      clearTimeout(this.stepTimer);
      this.stepTimer = setTimeout(() => { if (this.alive && this.ph === ph && ph.name === name) this.nextStep(); }, 650);
    }
    // the 2D finishTq: same formulas, same fields
    finish() {
      if (this.finished) return;
      this.finished = true;
      const q = this.q, G = this.G;
      if (this.ph && this.ph.exit) this.ph.exit();
      this.ph = { name: 'done', panel() {}, tick() {} };
      this.rodGrab = null; this.carry = null;
      this.pen.visible = false;
      this.cursor(null, ''); this.stageCursor('');
      this.showZones(false);
      this.tq.guide.visible = false;
      this.app.pp.set({ pause: false });   // nothing left to step away from
      const twistScore = clamp(100 - q.over * 6 - Math.max(0, (q.twistTime || 10) - 14) * 1.5, 0, 100);
      const lockScore = clamp(100 - q.misLocks * 18, 0, 100);
      const score = Math.round(q.placeScore * 0.35 + q.slackScore * 0.1 + twistScore * 0.35 + lockScore * 0.2);
      G.steps = { place: q.placeScore, twist: Math.round(twistScore), lock: lockScore };
      this.updateTools();
      this.app.submit({ score, seg: q.seg || 'upper', frac: Math.round((q.frac || 0.2) * 1000) / 1000, pressure: Math.round(q.P), over: Math.round(q.over * 10) / 10, misLocks: q.misLocks, time: q.time, steps: { place: q.placeScore, twist: Math.round(twistScore), lock: lockScore } });
    }

    stageCursor(cls) { const c = `tq3-stage ${cls || ''}`.trim(); if (this.stage.className !== c) this.stage.className = c; }
    cursor(p, text, tone) { this.cur.p = p; this.cur.text = text || ''; this.cur.tone = tone || ''; }
    flashOnce(type, text, ms) { const n = performance.now(); if (this.lastFlash === text && n - this.lastFlashAt < 1800) return; this.lastFlash = text; this.lastFlashAt = n; this.app.pp.flash(type, text, ms || 2000); }
    tag(id, on, p3, text, tone) {
      let e = this.tags[id];
      if (!e) { e = this.tags[id] = el('div', 'tq3-tag', '<b><i></i><span></span></b>'); this.app.root.appendChild(e); e._t = ''; e._c = ''; }
      if (!on || !p3) { if (e.classList.contains('on')) e.classList.remove('on'); return; }
      const pr = this.S.project(p3);
      if (!pr.visible) { e.classList.remove('on'); return; }
      if (!this.zoom) this.zoom = parseFloat(getComputedStyle(this.app.el).zoom) || 1;
      e.style.transform = `translate(${(pr.x * window.innerWidth / this.zoom).toFixed(1)}px,${(pr.y * window.innerHeight / this.zoom).toFixed(1)}px)`;
      if (e._t !== text) { e._t = text; e.querySelector('span').textContent = text; }
      const cls = `tq3-tag on ${tone || ''}`.trim();
      if (e.className !== cls) e.className = cls;
    }
    hideTags() { Object.keys(this.tags).forEach(k => this.tag(k, false)); }

    /* ─────────────── camera ─────────────── */
    frameStep(step, instant) {
      const S = this.S, leg = this.kind === 'leg';
      const uvAt = (s, t) => [s / this.W + 0.5, 0.5 - t / this.H];
      if (step === 'place') {
        // the strap zone, the wound (and the joint in between) and the strap waiting beside the limb
        const pts = [this.sOf(this.tIdeal())];
        if (this.d.injury) pts.push(this.wS);
        if (this.lowerWound && this.d.injury) pts.push(this.sOf(this.tj));
        const s0 = Math.min(...pts), s1 = Math.max(...pts);
        const width = clamp(s1 - s0 + (leg ? 0.2 : 0.16), leg ? 0.4 : 0.3, leg ? 0.62 : 0.48);
        S.controls.frame(uvAt((s0 + s1) / 2 - 0.012, this.Rs * 0.1), width, { pitch: 1.02, instant: !!instant });
        return;
      }
      const sB = this.lp.s;
      if (step === 'slack') { S.controls.frame(uvAt(sB - 0.012, this.Rs * 0.62), leg ? 0.38 : 0.31, { pitch: 1.45, instant: !!instant }); return; }
      if (step === 'write') { S.controls.frame(uvAt(sB - 0.01, this.Rs * A_W * 0.9), leg ? 0.34 : 0.3, { pitch: 1.2, instant: !!instant }); return; }
      // twist / lock: the windlass and the wound (to watch the bleeding stop)
      let sc = sB, width = leg ? 0.36 : 0.3;
      if (this.d.injury) { const gap = Math.abs(sB - this.wS); sc = (sB + this.wS) / 2; width = clamp(gap + (leg ? 0.22 : 0.18), leg ? 0.36 : 0.3, leg ? 0.56 : 0.46); }
      S.controls.frame(uvAt(sc, this.Rs * A_W * 0.8), width, { pitch: 1.16, instant: !!instant });
    }

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
      if (was && this.ph && this.ph.up) this.ph.up(e);
    }
    pointer() { if (this.ready && this.ph && this.ph.pointer && !this.finished && !this.app.result) this.ph.pointer(); }
    key(e) {
      if (/^Digit[1-9]$/.test(e.code || '')) return this.app.pp.key(e);
      if (this.finished || this.app.result) return false;
      if (this.ph && this.ph.key) return this.ph.key(e);
      return false;
    }
    px(p) { return { x: p.x * window.innerWidth, y: p.y * window.innerHeight }; }
    ray(p) {
      const v = this._ndc || (this._ndc = new THREE.Vector2());
      v.set(p.x * 2 - 1, -(p.y * 2 - 1));
      this.rc.setFromCamera(v, this.S.camera);
      return this.rc.ray;
    }
    rayPlane(p, point, normal) {
      const pl = this._pl || (this._pl = new THREE.Plane());
      pl.setFromNormalAndCoplanarPoint(normal, point);
      return this.ray(p).intersectPlane(pl, V3(0, 0, 0));
    }
    // screen distance (window px) from the cursor to a 3D point
    distPx(v3, p) { const a = this.S.project(v3), b = p || this.S.pointer; return Math.hypot((a.x - b.x) * window.innerWidth, (a.y - b.y) * window.innerHeight); }

    /* ─────────────── per frame ─────────────── */
    frame(dt, render) {
      if (!this.alive || !this.S) return;
      this.t += dt;
      if (this.anim) this.animTick(dt);
      if (this.ph && this.ph.tick) this.ph.tick(dt);
      this.loopTick(dt);
      this.bleedTick(dt);
      if (!render) return;
      this.poseTq(dt);
      this.drawCursor();
      const n = performance.now();
      if (n - this.uiAt > 120) { this.uiAt = n; if (this.ph && this.ph.panel) this.ph.panel(); }
    }
    // the loop eases toward where it is going (carried, back to its rest, on the limb)
    loopTick(dt) {
      const lp = this.lp;
      const kTarget = lp.mode === 'rest' ? 0 : lp.mode === 'free' ? 0 : 1;
      const rate = 6.5 * dt;
      lp.k = kTarget > lp.k ? Math.min(kTarget, lp.k + rate) : Math.max(kTarget, lp.k - rate);
      if (lp.sTarget !== undefined) lp.s = lerp(lp.s, lp.sTarget, 1 - Math.exp(-dt * 26));
      const fT = lp.mode === 'free' ? lp.freeTarget : lp.mode === 'rest' ? lp.rest : null;
      if (fT) lp.free.lerp(fT, 1 - Math.exp(-dt * 22));
      if (lp.tail === 'fast' && lp.tailK < 1) lp.tailK = Math.min(1, lp.tailK + dt / 0.45);
      // the band settles into the tissue as it is tightened
      const tight = clamp(this.q.P / this.tune.occlusion, 0, 1.3);
      const sinkT = (1 - lp.loose) * (this.onCloth(lp.s) ? 0.0002 + 0.0004 * tight : 0.0002 + 0.0006 * tight);
      lp.sink = lerp(lp.sink, sinkT, 1 - Math.exp(-dt * 10));
    }
    drawCursor() {
      const c = this.cur, S = this.S;
      const on = !this.finished && !this.app.result && (c.p !== null || !!c.text);
      this.curEl.classList.toggle('on', on);
      if (!on) return;
      if (!this.zoom) this.zoom = parseFloat(getComputedStyle(this.app.el).zoom) || 1;
      const x = S.pointer.x * window.innerWidth / this.zoom, y = S.pointer.y * window.innerHeight / this.zoom;
      this.curEl.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`;
      const cls = `tq3-cur on ${c.p === null ? 'noring' : ''} ${c.tone}`;
      if (this.curEl.className !== cls) this.curEl.className = cls;
      if (c.p !== null) this.curFg.setAttribute('stroke-dasharray', `${(clamp(c.p, 0, 1) * 119.4).toFixed(1)} 120`);
      if (this.curTx.textContent !== c.text) this.curTx.textContent = c.text;
    }
    // the 2D tqBleed: bleeding from the strap pressure (none without a wound)
    tqBleed() {
      const G = this.G, q = this.q, tune = this.tune;
      G.pulseAmp = clamp(1 - q.P / tune.occlusion, 0, 1);
      if (!this.d.injury) { G.b = 0; return; }
      const covers = q.placed && !this.spot(q.t).below;
      G.b = covers ? Math.pow(clamp(1 - q.P / tune.occlusion, 0, 1), 1.25) : 1;
      // a strap below arterial pressure but above venous pressure makes it bleed MORE
      if (covers && q.P > 30 && q.P < tune.occlusion * 0.55) G.b = Math.min(1.25, G.b * 1.18);
    }
    // the wound bleeds by G.b: ooze in the wound, spurts on each beat when arterial, a pool spreading
    bleedTick(dt) {
      const S = this.S, G = this.G, inj = this.d.injury;
      if (!inj || !this.w) return;
      const res = this.app.result;
      const bleed = Math.max(0, num(inj.bleed, 0));
      const flow = bleed * G.b;
      if (!res) G.lost += flow * dt / 60;
      G.flowNow = flow;
      this.beatT = (this.beatT || 0) - dt;
      let beat = false;
      if (this.beatT <= 0) { this.beatT = 60 / clamp(G.hr || 90, 30, 200); beat = true; }
      const intensity = clamp(Math.log10(1 + bleed) / 2.4, 0.15, 1) * G.b;
      const vis = !res ? clamp(1 + 1.8 * Math.log2(1 + bleed / 3), 0.8, 12) * G.b : 0;
      const cur = this.oozeVis || 0;
      this.oozeT = (this.oozeT || 0) - dt;
      if ((Math.abs(vis - cur) > Math.max(0.35, cur * 0.18) && this.oozeT <= 0) || ((vis < 0.05) !== (cur < 0.05))) {
        S.fluids.bleed(this.w, vis > 0.05 ? vis : 0); this.oozeVis = vis > 0.05 ? vis : 0; this.oozeT = 0.4;
      }
      if (beat && inj.arterial && intensity > 0.05 && !res) {
        const sp = S.surfaceAt(this.wUv);
        sp.point.addScaledVector(sp.normal, 0.0015);
        S.fluids.drops(sp.point, Math.round(2 + 9 * intensity), BLOOD, 0.22 + 0.5 * intensity);
        if (intensity > 0.3) S.layers.paint('wet', this.wUv, 0.006, 0.2, { hardness: 0.1 });
      }
      this.poolT = (this.poolT || 0) - dt;
      if (this.poolT <= 0 && intensity > 0.03 && !res) {
        this.poolT = 0.32;
        const R = Math.random, grow = 1 + Math.min(2.2, G.lost / 160);
        const a = R() * TAU, dd = this.wRad + (1 + R() * 5) * MM * grow;
        const uv = S.stToUv(this.wST[0] + Math.cos(a) * dd, this.wST[1] + Math.abs(Math.sin(a)) * dd * 0.8 + R() * 4 * MM * grow);
        S.layers.paint('blood', uv, [(1.6 + R() * 3) * MM * grow, (1.2 + R() * 2) * MM * grow], 0.05 + 0.14 * intensity, { hardness: 0.3, grain: 0.3, grainScale: 150, angle: R() * Math.PI });
      }
    }

    /* ─────────────── panel readouts ─────────────── */
    painLevel() { const q = this.q, tune = this.tune; return clamp(Math.round(clamp(q.P / tune.occlusion, 0, 1.25) * 7.2 + (q.P > tune.occlusion + tune.overMargin ? 2 : 0)), 0, 10); }
    tqPanel() {
      const G = this.G, q = this.q, tune = this.tune;
      const over = q.P > tune.occlusion + tune.overMargin, occ = q.P >= tune.occlusion;
      const maxP = tune.occlusion + tune.overMargin * 1.7;
      const flow = (this.d.injury ? num(this.d.injury.bleed, 0) : 0) * G.b;
      const pain = this.painLevel();
      this.app.pp.set({
        stats: [
          { id: 'bleed', label: T('st_bleed', 'Bleed'), value: flow.toFixed(1), unit: 'mL/min', tone: flow > 3 ? 'red' : 'teal' },
          { id: 'press', label: T('st_press', 'Pressure'), value: String(Math.round(q.P)), unit: 'mmHg', tone: over ? 'red' : occ ? 'teal' : '' },
          { id: 'pulse', label: T('st_distal', 'Distal pulse'), value: (G.pulseAmp || 0) > 0.04 ? T('present', 'Present') : T('absent', 'Absent'), small: true, tone: (G.pulseAmp || 0) > 0.04 ? 'amber' : 'teal' },
          { id: 'pain', label: T('tq3_st_pain', 'Pain'), value: `${pain}`, unit: '/10', tone: pain >= 8 ? 'red' : pain >= 5 ? 'amber' : '' },
        ],
        wide: { label: T('w_occlusion', 'Occlusion'), value: over ? T('over', 'Over') : `${Math.min(100, Math.round((q.P / tune.occlusion) * 100))}`, unit: over ? '' : '%', tone: over ? 'red' : occ ? 'teal' : '', meter: { value: q.P / maxP, zone: [tune.occlusion / maxP, (tune.occlusion + tune.overMargin) / maxP], tone: over ? 'red' : '' }, caption: over ? T('cap_over', 'Ease off: over-tightened') : occ ? T('cap_occ', 'Artery closed') : T('cap_twist', 'Keep turning'), captionTone: over ? 'red' : occ ? 'teal' : '' },
      });
    }

    /* ═════════════════════════════ 1. PLACE IT HIGH AND TIGHT ═════════════════════════════ */
    phPlace() {
      const g = this, q = this.q, lp = this.lp;
      this.showZones(true);
      if (this.d.injury) this.S.markers.set('wound', { uv: this.wUv, kind: 'dashed', color: 0xe5484d, size: Math.max(0.026, this.wRad * 2 + 0.016), pulse: true });
      this.frameStep('place', this.stepIdx === 0 && !this.placeFramed);
      this.placeFramed = true;
      if (lp.mode !== 'loose') { lp.mode = 'rest'; }
      lp.tail = 'pull'; lp.pull = 0; lp.loose = 1; lp.drop = 0; lp.fold = 0;
      const jointWord = this.kind === 'leg' ? T('knee', 'knee') : T('elbow', 'elbow');
      return {
        hints: [{ keys: [T('k_drag', 'Drag')], label: T('tq3_h_place', 'put the strap on the limb') }],
        panelInit() {
          return {
            title: T('ph_place', 'Place it high and tight'),
            text: g.d.injury
              ? T('tq3_place_t', '**Grab the tourniquet** and drag the loop onto the limb **above the wound**, into a teal band, and let go. Never over the %s.', jointWord)
              : T('tq3_place_t_noinj', '**Grab the tourniquet** and drag the loop onto the limb, **high on the upper part** (the teal band), and let go. Never over the %s.', jointWord),
          };
        },
        down() {
          if (this.finished || g.carry) return;   // placed: the next step is on its way
          if (g.overStrap()) { g.carry = { t0: g.t }; lp.mode = 'free'; g.carryAim(); NZA.audio.click(520); }
          else g.flashOnce('warn', T('tq3_grab_first', 'Click and hold the tourniquet first, then drag it onto the limb.'), 1800);
        },
        pointer() { if (g.carry && g.lmb) g.carryAim(); },
        up() { if (g.carry) { g.carryAim(); g.drop(); } },
        tick() {
          const S = g.S;
          G0(g);
          if (g.carry) {
            if (g.lmb) g.carryAim();
            g.stageCursor('grabbing');
            if (lp.mode === 'on') { const sp = g.spot(g.tOfS(lp.sTarget)); g.cursor(null, g.spotText(sp), g.spotTone(sp)); }
            else g.cursor(null, T('tq3_cur_onto', 'Onto the limb, above the wound'), '');
          } else {
            const over = !this.finished && g.overStrap();
            g.stageCursor(over ? 'grab' : '');
            g.cursor(null, over ? T('tq3_cur_grab', 'Grab it') : '', '');
          }
          // tags over the bands (never under the HUD card / panel)
          (g.zones || []).forEach(z => {
            const tt = z.id === 'high' ? Math.max(z.t, (g.zoneEnd || {}).high || z.t) : z.t;
            const zs = g.sOf(tt), rr = g.baseR(zs), p3 = V3(zs, rr * Math.cos(-0.45) - g.Rs + 0.012, rr * Math.sin(-0.45));
            const pr = S.project(p3), clear = pr.x * window.innerWidth > 460 && pr.x < 0.86 && pr.y > 0.06;
            const text = z.id === 'joint' ? (g.kind === 'leg' ? T('knee_up', 'KNEE') : T('elbow_up', 'ELBOW')) : z.id === 'ideal' ? T('tq3_zone_ideal', '%s–%s cm above the wound', g.tune.idealAbove[0], g.tune.idealAbove[1]) : T('lbl_high', 'High and tight');
            g.tag(z.id, !g.carry && clear, p3, text, z.id === 'joint' ? 'red' : 'teal');
          });
        },
        exit() { g.hideTags(); g.showZones(false); g.S.markers.remove('wound'); },
        panel() {
          const t = lp.mode === 'on' || lp.mode === 'loose' ? g.tOfS(lp.mode === 'on' ? lp.sTarget : lp.s) : null;
          const sp = t === null ? null : g.spot(t);
          g.app.pp.set({
            stats: [
              { id: 'pos', label: T('st_pos', 'Position'), value: !sp ? '--' : sp.noWound ? (sp.highTight ? T('high', 'High') : T('low', 'Low')) : sp.below ? T('below', 'Below') : `${Math.max(0, Math.round(sp.cm))}`, unit: !sp || sp.noWound || sp.below ? '' : T('cm_above', 'cm above'), tone: sp && (sp.below || sp.onJoint) ? 'red' : '' },
              { id: 'seg', label: T('st_on', 'On'), value: !sp ? '--' : sp.seg === 'upper' ? (g.kind === 'leg' ? T('thigh', 'Thigh') : T('upper_arm', 'Upper arm')) : (g.kind === 'leg' ? T('calf', 'Lower leg') : T('forearm', 'Forearm')), small: true },
              { id: 'mis', label: T('tq3_st_misplaced', 'Misplaced'), value: String(q.misplaced), tone: q.misplaced ? 'amber' : '' },
            ],
            wide: { label: T('w_place', 'Placement'), value: !sp ? '--' : sp.below ? T('bad', 'Bad') : sp.onJoint ? T('joint', 'Joint') : T('ok', 'OK'), tone: sp && (sp.below || sp.onJoint) ? 'red' : '', meter: { value: t === null ? 0 : 1 - t, zone: g.d.injury ? [clamp(1 - g.tw + g.tune.idealAbove[0] / g.tune.length, 0, 1), clamp(1 - g.tw + g.tune.idealAbove[1] / g.tune.length, 0, 1)] : [1 - 0.35 * g.tj, 1], mark: t === null ? undefined : 1 - t, noFill: true }, caption: T('cap_place', '2–3 finger widths above the wound is ideal'), captionTone: 'teal' },
          });
        },
      };
    }
    // is the cursor on the tourniquet (lying beside the limb, or loose on it)?
    overStrap() {
      const lp = this.lp, S = this.S;
      if (lp.mode === 'loose' || lp.mode === 'placed') {
        const hit = S.raycast(S.pointer);
        if (hit && Math.abs(hit.s - lp.s) < BW * 0.9) return true;
        return this.distPx(this.tq.plate.position) < window.innerHeight * 0.06;
      }
      // lying flat: near its centre line (a few samples along it) or the hardware
      const C = lp.free, lim = window.innerHeight * 0.055;
      for (let i = -4; i <= 4; i++) if (this.distPx(V3(C.x + i * 0.02, C.y, C.z)) < lim) return true;
      return this.distPx(this.tq.plate.position) < lim || this.distPx(this.tq.tab.position) < lim;
    }
    // carried: on the limb under the cursor (a loose loop round it), or above the blanket
    carryAim() {
      const S = this.S, lp = this.lp;
      const hit = S.raycast(S.pointer);
      if (hit) {
        const sMin = this.sOf(this.tMax), sMax = this.sOf(this.tMin);
        lp.sTarget = clamp(hit.s, sMin, sMax);
        if (lp.mode !== 'on') { lp.mode = 'on'; if (lp.k < 0.05) lp.s = lp.sTarget; }
        return;
      }
      lp.mode = 'free';
      let p = null;
      const cl = S._cloth;
      if (cl) { const h = this.ray(S.pointer); this.rc.ray.copy(h); const x = this.rc.intersectObject(cl, false)[0]; if (x) p = x.point.clone(); }
      if (!p) p = this.rayPlane(S.pointer, V3(0, this.clothY, 0), V3(0, 1, 0));
      if (p) { p.y += 0.03; lp.freeTarget = p; }
    }
    drop() {
      const lp = this.lp, q = this.q;
      this.carry = null;
      if (lp.mode !== 'on' || lp.sTarget === undefined) {
        lp.mode = 'rest'; lp.freeTarget = null; NZA.audio.click(420);
        return;
      }
      lp.s = lp.sTarget; lp.sTarget = undefined;
      const t = clamp(this.tOfS(lp.s), this.tMin, this.tMax);
      q.t = t;
      const sp = this.spot(t);
      if (sp.below || sp.onJoint) {
        q.misplaced += 1;
        lp.mode = 'loose';
        NZA.audio.fail();
        if (sp.below) this.app.pp.flash('bad', T('tq_below_wound', 'That is below the wound. The bleeding comes from above: move it up.'), 2200);
        else this.app.pp.flash('bad', T('tq_joint', 'Never over a joint: it will not compress the artery. Move it off the %s.', this.kind === 'leg' ? T('knee', 'knee') : T('elbow', 'elbow')), 2200);
        return;
      }
      this.confirmPlace(sp);
    }
    confirmPlace(sp, silent) {
      if (this.ph && this.ph.name === 'place' && this.ph.finished) return;   // placed once: one tqPlace post
      const q = this.q, lp = this.lp;
      q.placeScore = this.placeScoreFor(sp);
      q.placed = true; q.seg = sp.seg; q.frac = sp.frac;
      lp.mode = 'placed';
      NZA.post('treat:tqPlace', { seg: sp.seg, frac: Math.round(sp.frac * 1000) / 1000 });
      if (silent) return;
      NZA.audio.click(700);
      this.stepDone(sp.highTight || this.spotTone(sp) === 'teal' ? T('tq3_ok_place', 'Good spot. Now pull the slack out.') : T('tq3_ok_place_meh', 'It will do. Now pull the slack out.'), 1600);
    }

    /* ═════════════════════════════ 2. PULL THE SLACK ═════════════════════════════ */
    phSlack() {
      const g = this, q = this.q, lp = this.lp, tune = this.tune;
      lp.mode = 'placed'; lp.tail = 'pull'; lp.pull = 0; lp.loose = 1;
      this.frameStep('slack');
      const ph = {
        drag: null,
        hints: [{ keys: [T('k_drag', 'Drag')], label: T('h_pull', 'pull the strap') }],
        panelInit() {
          return {
            title: T('ph_slack', 'Pull the strap tight'),
            text: T('tq3_slack_t', '**Drag the red tab** on the free end away from the buckle to pull all the slack out. Let go inside the green band: snug against the limb.'),
          };
        },
        nearTab() { return g.tq.tabEnd && g.distPx(g.tq.tab.position) < window.innerHeight * 0.07; },
        down() {
          if (this.finished) return;
          if (this.nearTab()) { const p = g.px(g.S.pointer); this.drag = { x: p.x, y: p.y, base: lp.pull }; NZA.audio.click(520); }
          else g.flashOnce('warn', T('tq3_slack_grab', 'Grab the red tab at the end of the free strap.'), 1800);
        },
        pointer() { if (this.drag && g.lmb) this.aim(); },
        aim() {
          // the pull runs along the band's way out of the buckle, as it shows on screen
          const B = g._fb; if (!B) return;
          const a = g.S.project(B.p), b = g.S.project(B.p.clone().addScaledVector(B.t, 0.05).addScaledVector(B.n, 0.011));
          let dx = (b.x - a.x) * window.innerWidth, dy = (b.y - a.y) * window.innerHeight;
          const L = Math.hypot(dx, dy) || 1; dx /= L; dy /= L;
          const p = g.px(g.S.pointer);
          const along = (p.x - this.drag.x) * dx + (p.y - this.drag.y) * dy;
          lp.pull = clamp(this.drag.base + along / (SLACK_PX * window.innerHeight), 0, 1.25);
        },
        up() {
          if (!this.drag) return;
          this.aim();
          this.drag = null;
          if (lp.pull >= 0.62 && !this.finished) {
            const good = lp.pull >= 0.75 && lp.pull <= 1.0;
            q.slack = clamp(lp.pull, 0, 1);
            q.slackScore = good ? 100 : lp.pull > 1.0 ? 70 : 78;
            q.P = q.slack * 0.38 * tune.occlusion;
            NZA.audio.click(760);
            lp.tail = 'fast'; lp.tailK = 0;
            this.finished = true;
            g.app.pp.flash(good ? 'ok' : 'warn', good ? T('ok_slack', 'Slack out. Now the windlass.') : lp.pull > 1.0 ? T('slack_over', 'Yanked hard, the buckle slipped a little.') : T('slack_some', 'Some slack left: you will need more turns.'), 1500);
            clearTimeout(g.stepTimer);
            g.stepTimer = setTimeout(() => { if (g.alive && g.ph === ph) g.nextStep(); }, 600);
          } else if (lp.pull > 0.08) g.flashOnce('warn', T('tq3_slack_more', 'Pull further: let go inside the green band.'), 1600);
        },
        tick(dt) {
          G0(g);
          if (!this.drag && !this.finished) lp.pull = Math.max(0, lp.pull - dt * 0.6);
          if (!this.finished) lp.loose = clamp(1 - lp.pull / 0.78, 0, 1);
          const pull = lp.pull, near = this.nearTab();
          g.stageCursor(this.drag ? 'grabbing' : near ? 'grab' : '');
          if (this.finished) { g.cursor(null, ''); return; }
          if (this.drag) g.cursor(clamp(pull / 1.25, 0, 1), pull > 1 ? T('tq3_cur_hard', 'Too hard') : pull >= 0.75 ? T('tq3_cur_snug', 'Snug: let go') : T('tq3_cur_pull', 'Pull…'), pull > 1 ? 'red' : pull >= 0.75 ? 'teal' : 'amber');
          else g.cursor(null, near ? T('lbl_pull', 'Pull') : '', 'teal');
          g.tag('pull', !this.drag && pull < 0.05, g.tq.tab.position, T('lbl_pull', 'Pull'), 'teal');
        },
        exit() { g.tag('pull', false); },
        panel() {
          const pull = lp.pull;
          g.app.pp.set({ stats: [{ id: 'slack', label: T('st_slack', 'Slack out'), value: String(Math.round(clamp(pull, 0, 1) * 100)), unit: '%' }], wide: { label: T('w_strap', 'Tension'), value: pull > 1 ? T('hard', 'Hard') : pull >= 0.75 ? T('good', 'Good') : T('slack', 'Slack'), meter: { value: clamp(pull / 1.25, 0, 1), zone: [0.75 / 1.25, 1.0 / 1.25], tone: pull > 1 ? 'red' : '' }, caption: T('cap_slack', 'Release inside the green band'), captionTone: 'teal' } });
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 3. TWIST THE WINDLASS ═════════════════════════════ */
    // the rod's turning plane: the plate's frame (x = along the limb, y = out, z = along the band)
    rodPlane() {
      const P = this.tq.plate;
      P.updateMatrixWorld(true);
      const o = V3(0, H_TURN, 0).applyMatrix4(P.matrixWorld);
      const n = V3(0, 1, 0).transformDirection(P.matrixWorld), w = V3(1, 0, 0).transformDirection(P.matrixWorld), t = V3(0, 0, 1).transformDirection(P.matrixWorld);
      return { o, n, w, t };
    }
    // the rod angle the cursor points at (θ = 0 along the band, π/2 along the limb) and its distance
    rodAim(p) {
      const pl = this.rodPlane(), hit = this.rayPlane(p || this.S.pointer, pl.o, pl.n);
      if (!hit) return null;
      const v = hit.sub(pl.o), x = v.dot(pl.w), z = v.dot(pl.t);
      return { a: Math.atan2(x, z), r: Math.hypot(x, z) };
    }
    nearRod() { const r = this.rodAim(); return !!r && r.r < ROD_L * 0.68; }
    grabRod() { if (this.q.locked) return; const r = this.rodAim(); this.rodGrab = { la: r ? r.a : null, tick: 0 }; NZA.audio.click(560); }
    // a pointer move while the rod is held: the rod follows the cursor round; each turn tightens
    turnRod() {
      const gr = this.rodGrab; if (!gr || this.q.locked) return;
      const q = this.q, tune = this.tune;
      const r = this.rodAim();
      if (!r || r.r < 0.011) { gr.la = null; return; }
      if (gr.la === null) { gr.la = r.a; return; }
      const da = angDiff(r.a, gr.la);
      gr.la = r.a;
      if (Math.abs(da) > 1.4) return;     // passed through the hub: start again from here
      if (!this.rodDir && Math.abs(da) > 0.06) this.rodDir = da > 0 ? 1 : -1;
      const fwd = da * (this.rodDir || 1);
      const minP = q.slack * 0.38 * tune.occlusion * 0.6, maxP = tune.occlusion + tune.overMargin * 1.7;
      q.theta += da;
      q.P = clamp(q.P + (tune.turnGain * fwd) / TAU, minP, maxP);
      gr.tick += Math.abs(fwd);
      if (gr.tick > 0.52) { gr.tick = 0; NZA.audio.tick(); }
    }
    // per frame while the windlass can turn: unwinding when let go, over-tightening, pain
    twistTick(dt) {
      const q = this.q, tune = this.tune;
      if (!q.locked && (!this.rodGrab || !this.lmb)) {
        const minP = q.slack * 0.38 * tune.occlusion * 0.6;
        if (q.P > minP && tune.unwind > 0) {
          const dP = Math.min(q.P - minP, tune.unwind * dt);
          q.P -= dP;
          q.theta -= (this.rodDir || 1) * (dP / tune.turnGain) * TAU;
        }
      }
      if (q.P > tune.occlusion + tune.overMargin && !q.locked) {
        q.over += dt;
        if (!this.overWarned) { this.overWarned = true; this.app.pp.flash('bad', T('tq_over', 'Too tight! Nerves and muscle get crushed. Ease off a little.'), 2200); NZA.audio.alarm(1); this.S.controls.shake(0.25, 300); }
      } else this.overWarned = false;
      // pain: the patient feels every turn
      const f = q.P / tune.occlusion;
      if (f > 0.62 && !this.painSaid) { this.painSaid = true; this.app.pp.flash('warn', T('tq3_pain', 'The patient cries out: a tourniquet hurts. That is normal, keep turning.'), 2400); this.S.controls.shake(0.12, 260); }
      const band = Math.floor(f * 4);
      if (band > (this.painBand || 0) && band >= 2) this.S.controls.shake(0.06 + 0.03 * band, 200);
      this.painBand = Math.max(this.painBand || 0, band);
      this.tqBleed();
    }
    phTwist(o) {
      const g = this, q = this.q, lp = this.lp, tq = this.tq;
      lp.mode = 'placed'; lp.loose = 0; lp.tail = 'fast'; if (o.instant) lp.tailK = 1;
      this.frameStep('twist');
      tq.guide.visible = true;
      const ph = {
        okT: 0,
        hints: [{ keys: [T('k_lmb', 'Hold LMB')], label: T('tq3_h_grab', 'on the rod') }, { keys: [T('k_circle', 'Circle')], label: T('h_twist', 'twist') }],
        panelInit() {
          return {
            title: T('ph_twist', 'Twist the windlass'),
            text: T('tq3_twist_t', '**Hold {LMB} on the rod and turn it round** like a dial: it follows the cursor. Keep turning until the bleeding stops and the distal pulse is gone. Let go and it unwinds. Do not over-tighten.'),
          };
        },
        down() { if (g.nearRod()) g.grabRod(); else g.flashOnce('warn', T('tq3_rod_grab', 'Hold the button down on the teal rod, then turn it round.'), 1800); },
        pointer() { if (g.rodGrab && g.lmb) g.turnRod(); },
        up() { if (g.rodGrab) { g.turnRod(); g.rodGrab = null; } },
        tick(dt) {
          // (the rod turns on pointer events only: frames walk an interpolated pointer)
          g.twistTick(dt);
          const stopped = g.d.injury ? g.G.b <= 0.001 : q.P >= g.tune.occlusion;
          if (stopped) this.okT += dt; else this.okT = 0;
          if (this.okT > 0.7 && !this.finished) {
            this.finished = true;
            q.twistTime = g.t - this.t0;
            NZA.audio.success();
            g.app.pp.flash('ok', T('ok_twist', 'No distal pulse, bleeding stopped. Lock it before it unwinds!'), 1800);
            clearTimeout(g.stepTimer);
            g.stepTimer = setTimeout(() => { if (g.alive && g.ph === ph) g.nextStep(); }, 350);
          }
          g.rodCursor();
          tq.guide.rotation.z += dt * (g.rodGrab ? 0 : 0.6);
          g.M.guide.opacity = g.rodGrab ? 0.25 : 0.45 + 0.2 * Math.sin(g.t * 4);
        },
        exit() {},
        panel() { g.tqPanel(); },
      };
      return ph;
    }
    rodCursor() {
      const q = this.q, tune = this.tune;
      if (this.rodGrab && this.lmb) {
        const over = q.P > tune.occlusion + tune.overMargin, occ = q.P >= tune.occlusion;
        this.stageCursor('grabbing');
        this.cursor(clamp(q.P / tune.occlusion, 0, 1), over ? T('tq3_cur_over', 'Too tight: turn back') : occ ? T('cap_occ', 'Artery closed') : T('tq3_cur_turn', 'Turning… bleeding slows'), over ? 'red' : occ ? 'teal' : 'amber');
      } else {
        const near = this.nearRod();
        this.stageCursor(near ? 'grab' : '');
        this.cursor(null, near ? T('tq3_cur_hold_rod', 'Hold LMB and turn') : '', '');
      }
    }

    /* ═════════════════════════════ 4. LOCK IT, MARK THE TIME ═════════════════════════════ */
    rodAligned() {
      const q = this.q, m = x => ((x % Math.PI) + Math.PI) % Math.PI, clipA = -Math.PI / 2;
      const d = Math.abs(angDiff(m(q.theta), m(clipA))) * 180 / Math.PI;
      return d <= this.tune.clipWindow || Math.abs(d - 180) <= this.tune.clipWindow;
    }
    phLock() {
      const g = this, q = this.q, lp = this.lp, tq = this.tq, tune = this.tune, KEY = this.KEY;
      lp.mode = 'placed'; lp.loose = 0; lp.tail = 'fast'; lp.tailK = 1;
      if (!q.locked) { this.frameStep('twist'); tq.guide.visible = true; }
      const ph = {
        phase: q.locked ? 'write' : 'lock', writing: null,
        hints: q.locked
          ? [{ keys: [T('k_drag', 'Drag')], label: T('tq3_h_write', 'write the time') }, { keys: [keyLabel(KEY.lock)], label: T('tq3_h_write_key', 'write it') }]
          : [{ keys: [T('k_circle', 'Circle')], label: T('h_align', 'align') }, { keys: [T('tq3_k_letgo', 'Let go')], label: T('tq3_h_clip', 'into the clip') }, { keys: [keyLabel(KEY.lock)], label: T('h_lock', 'lock') }],
        panelInit() {
          return this.phase === 'write' ? g.writeText() : {
            title: T('ph_lock', 'Lock the windlass'),
            text: T('tq3_lock_t', 'Keep turning until the rod lines up with the **clip** (it lights up teal), then **let go**: it drops in. Or press {%s}. Keep it tight while you do it.', keyLabel(KEY.lock)),
          };
        },
        key(e) {
          if (e.code !== KEY.lock && e.code !== KEY.confirm && e.code !== 'Enter') return false;
          if (this.phase === 'lock') g.tryLock(); else if (this.phase === 'write') g.writeAll();
          return true;
        },
        down() {
          if (this.phase === 'lock' && !q.locked) {
            if (g.nearRod()) g.grabRod();
            else if (g.nearClip()) g.tryLock();
            else g.flashOnce('warn', T('tq3_rod_grab', 'Hold the button down on the teal rod, then turn it round.'), 1800);
          } else if (this.phase === 'write') {
            const l = g.labelAim();
            if (l && l.inside) { this.writing = { x: l.x }; NZA.audio.click(640); }
            else g.flashOnce('warn', T('tq3_write_here', 'Write on the white TIME label on the strap.'), 1800);
          }
        },
        pointer() {
          if (this.phase === 'lock' && g.rodGrab && g.lmb) g.turnRod();
          if (this.phase === 'write' && this.writing && g.lmb) g.scribble(this);
        },
        up() {
          if (this.phase === 'lock' && g.rodGrab) {
            g.turnRod(); g.rodGrab = null;
            if (g.rodAligned() && q.P >= tune.occlusion) g.lockRod();
          }
          if (this.phase === 'write' && this.writing) { g.scribble(this); this.writing = null; }
        },
        tick(dt) {
          if (this.phase === 'lock') {
            if (q.locked) return;
            g.twistTick(dt);
            const ok = g.rodAligned() && q.P >= tune.occlusion;
            g.M.hook.emissiveIntensity = lerp(g.M.hook.emissiveIntensity, ok ? 0.9 + 0.3 * Math.sin(g.t * 9) : 0, 1 - Math.exp(-dt * 14));
            if (g.rodGrab && g.lmb && ok) { g.stageCursor('grabbing'); g.cursor(1, T('tq3_cur_letgo', 'In line: let go'), 'teal'); }
            else g.rodCursor();
            tq.guide.rotation.z += dt * (g.rodGrab ? 0 : 0.6);
            g.M.guide.opacity = g.rodGrab ? 0.22 : 0.42;
            return;
          }
          if (this.phase === 'write') {
            G1(g);
            const l = g.labelAim();
            const onL = !!(l && l.inside);
            g.penAt(l);
            g.stageCursor(onL || this.writing ? 'hide' : '');
            g.cursor(this.writing ? q.written : null, this.writing ? T('tq3_cur_writing', 'Writing…') : onL ? T('tq3_cur_write', 'Hold LMB and write') : '', 'teal');
            g.M.hook.emissiveIntensity = Math.max(0, g.M.hook.emissiveIntensity - dt * 2);
          }
        },
        exit() { g.pen.visible = false; g.tq.guide.visible = false; },
        panel() {
          if (this.phase === 'write') {
            g.app.pp.set({ stats: [{ id: 'time', label: T('dev_time', 'Time on'), value: q.time || '--:--' }, { id: 'press', label: T('st_press', 'Pressure'), value: String(Math.round(q.P)), unit: 'mmHg', tone: 'teal' }], wide: { label: T('tq3_w_label', 'Label'), value: String(Math.round(q.written * 100)), unit: '%', meter: { value: q.written }, caption: T('tq3_cap_label', 'Write the time it went on'), captionTone: 'teal' } });
          } else g.tqPanel();
        },
      };
      if (q.locked) this.enterWrite(ph, true);
      return ph;
    }
    nearClip() { const tq = this.tq; return tq.hooks.some(h => this.distPx(h.getWorldPosition(V3(0, 0, 0))) < window.innerHeight * 0.05); }
    tryLock() {
      const q = this.q, tune = this.tune;
      if (q.locked || !this.ph || this.ph.phase !== 'lock') return;
      if (!this.rodAligned()) { q.misLocks += 1; NZA.audio.fail(); this.app.pp.flash('bad', T('lock_miss', 'The rod is not in the clip. Turn it until the clip lights up.'), 1600); return; }
      if (q.P < tune.occlusion) { q.misLocks += 1; NZA.audio.fail(); this.app.pp.flash('bad', T('lock_loose', 'It unwound: bleeding again. Twist it back first.'), 1600); return; }
      this.lockRod();
    }
    // the rod clicks into the clip, the windlass strap folds over it, then the time label
    lockRod(instant) {
      const q = this.q, ph = this.ph;
      if (q.locked) return;
      q.locked = true;
      this.rodGrab = null;
      if (!q.time) { const d = new Date(); q.time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; }
      const m = x => ((x % Math.PI) + Math.PI) % Math.PI;
      // nearest clip angle (θ ≡ π/2 mod π), keeping the turns already made
      const target = q.theta + ((((Math.PI / 2 - m(q.theta)) % Math.PI) + Math.PI * 1.5) % Math.PI - Math.PI / 2);
      this.tq.guide.visible = false;
      this.updateTools();
      if (instant) { q.theta = target; this.lp.drop = 1; this.lp.fold = 1; if (ph) this.enterWrite(ph, true); return; }
      NZA.audio.click(900);
      this.app.pp.flash('ok', T('tq3_ok_clip', 'In the clip. Close the strap over it…'), 1400);
      const th0 = q.theta;
      this.anim = { t: 0, T: 0.95, step: k => {
        q.theta = lerp(th0, target, smooth(0, 0.25, k));
        this.lp.drop = smooth(0.08, 0.3, k);
        this.lp.fold = smooth(0.35, 1, k);
      }, done: () => { NZA.audio.click(700); if (this.ph === ph) this.enterWrite(ph); } };
    }
    animTick(dt) {
      const a = this.anim;
      a.t += dt;
      const k = clamp(a.t / a.T, 0, 1);
      a.step(k);
      if (k >= 1) { this.anim = null; if (a.done) a.done(); }
    }
    writeText() {
      return {
        title: T('tq3_ph_write', 'Mark the time'),
        text: T('tq3_write_t', 'Write the time on the **TIME label**: hold {LMB} on it and scribble across, or press {%s}. It went on at **%s**.', keyLabel(this.KEY.lock), this.q.time || '--:--'),
      };
    }
    enterWrite(ph, quiet) {
      ph.phase = 'write';
      this.rodGrab = null;   // a press held through the lock animation must not block P
      this.frameStep('write');
      this.updateTools();
      this.app.pp.set(Object.assign({ hints: this.hintsFor([{ keys: [T('k_drag', 'Drag')], label: T('tq3_h_write', 'write the time') }, { keys: [keyLabel(this.KEY.lock)], label: T('tq3_h_write_key', 'write it') }]) }, this.writeText()));
      if (!quiet) NZA.audio.click(600);
    }
    // the cursor on the label: local coordinates (x along it, −1..1) and whether it is on it
    labelAim() {
      const L = this.tq.label;
      if (!L.visible) return null;
      L.updateWorldMatrix(true, false);
      const o = L.getWorldPosition(V3(0, 0, 0)), n = V3(0, 0, 1).transformDirection(L.matrixWorld);
      const hit = this.rayPlane(this.S.pointer, o, n);
      if (!hit) return null;
      const loc = L.worldToLocal(hit.clone());
      return { p: hit, n, x: loc.x / 0.025, y: loc.y / 0.01, inside: Math.abs(loc.x) < 0.029 && Math.abs(loc.y) < 0.0135 };
    }
    // the marker pen: tip on the label under the cursor, leaning toward you and to the right
    penAt(l) {
      const pen = this.pen;
      if (!l || !(l.inside || (this.ph && this.ph.writing))) { pen.visible = false; return; }
      const S = this.S, cam = S.camera;
      const right = V3(1, 0, 0).applyQuaternion(cam.quaternion), up = V3(0, 1, 0).applyQuaternion(cam.quaternion);
      const axis = l.n.clone().multiplyScalar(0.62).addScaledVector(right, 0.62).addScaledVector(up, 0.45).normalize();
      pen.position.copy(l.p).addScaledVector(l.n, this.ph && this.ph.writing ? 0.0004 : 0.004);
      pen.quaternion.setFromUnitVectors(V3(0, 1, 0), axis);
      pen.visible = true;
    }
    scribble(ph) {
      const l = this.labelAim(), q = this.q;
      if (!l || !ph.writing) return;
      if (l.inside) {
        const dx = Math.abs(l.x - ph.writing.x);
        if (dx < 1.2) q.written = clamp(q.written + dx * 0.42, 0, 1);
      }
      ph.writing.x = l.x;
      this.labelDirty(q.written >= 1);
      if (q.written >= 1) this.written();
    }
    labelDirty(force) { const q = this.q; if (force || Math.abs(q.written - (this.lastDrawn || 0)) > 0.03) { this.lastDrawn = q.written; this.drawLabel(); } }
    writeAll() { const q = this.q; if (q.written >= 1) return; q.written = 1; this.drawLabel(); this.written(); }
    written() {
      const ph = this.ph;
      if (!ph || ph.finished) return;
      ph.writing = null;
      this.pen.visible = false;
      this.stageCursor('');
      this.stepDone(T('ok_lock', 'Locked. Time written on the strap: %s', this.q.time), 2200);
    }

    /* ─────────────── state: restore a snapshot / a preview stage ─────────────── */
    // whether a snapshot belongs to this limb and wound (a pause is kept per patient + procedure)
    sameLimb(w) {
      if (!w || typeof w !== 'object') return false;
      const inj = this.d.injury;
      return String(w.reg) === String(this.region) && String(w.seg) === String(this.wSeg)
        && Math.abs(num(w.frac, -9) - this.wFrac) < 0.02 && String(w.id === undefined ? '' : w.id) === String(inj ? inj.id : '')
        && String(w.type === undefined ? '' : w.type) === String(inj ? inj.type || '' : '');
    }
    resetGame() {
      const q = this.q, lp = this.lp;
      Object.assign(q, { t: 0.2, placed: false, seg: null, frac: null, slack: 0, P: 0, theta: 0, locked: false, over: 0, misLocks: 0, misplaced: 0, placeScore: 100, slackScore: 0, twistTime: null, written: 0 });
      Object.assign(lp, { mode: 'rest', tail: 'pull', tailK: 0, pull: 0, loose: 1, drop: 0, fold: 0, k: 0 });
      this.rodDir = 0;
      this.drawLabel();
    }
    // set the game to a step with these values (k: 0 place · 1 slack · 2 twist · 3 lock / write)
    applyState(k, v) {
      const q = this.q, lp = this.lp;
      if (this.ph && this.ph.exit) this.ph.exit();
      this.ph = null;
      clearTimeout(this.stepTimer);
      Object.assign(q, v);
      delete q.twistT;
      if (k >= 1) {
        lp.s = this.sOf(q.t); lp.sTarget = undefined; lp.mode = 'placed'; lp.k = 1;
        const sp = this.spot(q.t);
        q.seg = sp.seg; q.frac = sp.frac; q.placed = true;
        // the strap prop on the ped comes back with the placement (a new session after a step away)
        NZA.post('treat:tqPlace', { seg: sp.seg, frac: Math.round(sp.frac * 1000) / 1000 });
      }
      if (k >= 2) { lp.loose = 0; lp.tail = 'fast'; lp.tailK = 1; lp.pull = q.slack; }
      if (k === 3 && q.locked) { lp.drop = 1; lp.fold = 1; }
      if (q.written > 0) this.drawLabel();
      this.tqBleed();
      this.stepIdx = k - 1;
      this.placeFramed = k > 0;
      this.nextStep();
      if (this.ph && k === 2 && v.twistT !== undefined) this.ph.t0 = this.t - v.twistT;
      this.poseTq(0, true);
    }
    // a snapshot → the same point. Every field is checked; anything unreadable falls back to the step start
    restore(r) {
      if (num(r.v, 0) !== 1 || !r.q || typeof r.q !== 'object') return false;
      const s = r.q, tune = this.tune;
      let k = Math.round(num(r.k, 0));
      if (!(k >= 0 && k <= 3)) k = 0;
      const maxP = tune.occlusion + tune.overMargin * 1.7;
      const v = {
        t: clamp(num(s.t, this.tIdeal()), this.tMin, this.tMax), misplaced: clamp(Math.round(num(s.mis, 0)), 0, 99),
        placeScore: clamp(Math.round(num(s.ps, 100)), 0, 100), slack: clamp(num(s.slack, 0), 0, 1), slackScore: clamp(Math.round(num(s.ss, 0)), 0, 100),
        P: clamp(num(s.P, 0), 0, maxP), theta: clamp(num(s.th, 0), -200, 200), over: clamp(num(s.over, 0), 0, 3600), misLocks: clamp(Math.round(num(s.ml, 0)), 0, 99),
        twistTime: s.tt === null || s.tt === undefined ? null : clamp(num(s.tt, 10), 0, MAX_SNAP_T), locked: num(s.locked, 0) === 1, written: clamp(num(s.wr, 0), 0, 1),
      };
      if (typeof s.time === 'string' && /^\d\d:\d\d$/.test(s.time)) v.time = s.time;
      const placedOk = num(s.placed, 0) === 1;
      // a step is entered only when the ones before it were done
      if (k >= 1 && (!placedOk || this.spot(v.t).below || this.spot(v.t).onJoint)) k = 0;
      if (k >= 2 && v.slack < 0.62) k = 1;
      if (k === 3 && v.twistTime === null) v.twistTime = 10;
      if (k < 3) { v.locked = false; v.written = 0; }
      if (k === 3 && v.locked && v.P < tune.occlusion) { v.locked = false; v.written = 0; }
      if (k < 2) { v.P = 0; v.theta = 0; v.over = 0; v.twistTime = null; }
      if (k < 1) { v.slack = 0; v.slackScore = 0; v.placeScore = 100; }
      this.t = clamp(num(r.t, 0), 0, MAX_SNAP_T);
      this.G.lost = clamp(num(r.lost, 0), 0, 1e5);
      this.rodDir = num(s.dir, 0) === -1 ? -1 : num(s.dir, 0) === 1 ? 1 : 0;
      if (k === 2) v.twistT = clamp(num(s.tw, 0), 0, MAX_SNAP_T);
      if (k === 0) {
        Object.assign(this.q, v);
        // a strap left loose on the limb (after a bad drop) stays there
        if (num(s.loose, 0) === 1) { this.lp.s = this.sOf(v.t); this.lp.mode = 'loose'; this.lp.k = 1; }
        this.stepIdx = -1; this.nextStep();
        return true;
      }
      this.applyState(k, v);
      return true;
    }
    // step away: a compact JSON-safe snapshot, null while a move is half done
    snapshot() {
      if (!this.S || !this.alive || this.finished || !this.ready || !this.ph) return null;
      const ph = this.ph, q = this.q, lp = this.lp;
      if (this.carry || this.rodGrab || this.anim || ph.drag || ph.writing) return null;
      let k = Math.max(0, this.stepIdx);
      // paused between finishing a step and the next one opening: carry on with the next
      if (ph.finished) { k = Math.min(3, k + 1); if (this.stepIdx === 3) return null; }
      const inj = this.d.injury;
      return {
        v: 1,
        w: { reg: this.region, seg: this.wSeg, frac: rnd(this.wFrac, 3), id: inj ? String(inj.id === undefined ? '' : inj.id) : '', type: inj ? String(inj.type || '') : '' },
        k, t: rnd(this.t, 2), lost: rnd(this.G.lost || 0, 1),
        q: {
          t: rnd(q.t, 4), placed: q.placed ? 1 : 0, loose: lp.mode === 'loose' ? 1 : 0, mis: q.misplaced, ps: q.placeScore,
          slack: rnd(q.slack, 3), ss: q.slackScore, P: rnd(q.P, 1), th: rnd(q.theta, 3), dir: this.rodDir, over: rnd(q.over, 2), ml: q.misLocks,
          tw: this.stepIdx === 2 && !ph.finished ? rnd(this.t - (ph.t0 || this.t), 2) : 0, tt: q.twistTime === null ? null : rnd(q.twistTime, 2),
          locked: q.locked ? 1 : 0, wr: rnd(q.written, 3), time: q.time || '',
        },
      };
    }

    /* ─────────────── preview: open at a stage (index.html?app=treat&mode=tq&stage=…) ─────────────── */
    jump(stage) {
      if (!this.ready) { this.pendingJump = stage; return; }
      const st = String(stage || '').toLowerCase(), tune = this.tune;
      const k = { place: 0, slack: 1, pull: 1, twist: 2, windlass: 2, lock: 3, clip: 3, write: 3, label: 3, time: 3, done: 3, result: 3 }[st];
      if (k === undefined || k === 0) return;
      const t = this.tIdeal();
      const v = { t, misplaced: 0, placeScore: this.placeScoreFor(this.spot(t)), slack: 0.86, slackScore: 100, P: 0, theta: 0, over: 0, misLocks: 0, twistTime: null, locked: false, written: 0 };
      if (k >= 2) { v.P = 0.86 * 0.38 * tune.occlusion; }
      if (k === 3) { v.P = tune.occlusion * 1.1; v.theta = 2 * TAU + 0.55; this.rodDir = 1; v.twistTime = 9.4; }
      this.applyState(k, v);
      if (k === 3 && /^(write|label|time|done|result)$/.test(st)) {
        this.q.theta = 2 * TAU + Math.PI / 2;
        this.lockRod(true);
        if (st === 'write' || st === 'label' || st === 'time') { this.q.written = st === 'time' ? 0 : 0.45; this.drawLabel(); }
        if (st === 'done' || st === 'result') { this.q.written = 1; this.drawLabel(); this.finish(); }
      }
    }
    // preview: drive the game to a stage, take the snapshot and open again with it
    previewPark(stage) {
      this.jump(stage);
      setTimeout(() => {
        if (!this.alive) return;
        const snap = this.snapshot();
        if (snap) NZA.demo('treat', Object.assign({}, this.d, { resume: snap }));
      }, 200);
    }

    /* ─────────────── teardown ─────────────── */
    dispose() {
      if (!this.alive) return;
      this.alive = false;
      const app = this.app;
      clearTimeout(this.stepTimer);
      window.removeEventListener('blur', this.onBlur);
      window.removeEventListener('resize', this.onResize);
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[treat] tq dispose', e); } this.S = null; }
      this.bin.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } });
      this.bin.clear();
      [this.stage, this.curEl, this.loadEl].concat(Object.values(this.tags || {})).forEach(n => { if (n && n.parentNode) n.parentNode.removeChild(n); });
      this.tags = {};
      app.full = false; app.opaque = false; delete app.camInput;
      app.el.classList.remove('nza-full');
      this.ph = null;
    }
  }
  // place / slack: the wound bleeds freely (no pressure yet); write: it stays as the clip holds it
  function G0(g) { g.G.b = g.d.injury ? 1 : 0; g.G.pulseAmp = 1; }
  function G1(g) { g.tqBleed(); }

  window.TreatTq3D = {
    ok() {
      if (!window.NZA3D || !THREE) return false;
      if (!NZA.inGame && /[?&]no3d=1\b/.test(location.search)) return false;
      try { return !!NZA3D.supported(); } catch (e) { return false; }
    },
    start(app, data) { return new Game(app, data); },
  };
})();
