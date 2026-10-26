/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · xray app · CAST 3D                              window.XrayCast3D
   The xray app's 'cast' mode as a full-screen 3D close-up on core/nza3d.js (the suture / burn
   look) under the shared procedure HUD (NZA.ui.ProcPanel). apps/xray/app.js starts it from
   modeCast() when WebGL2 works; its 2D canvas game stays the fallback.

   The limb (region from the open data) lies on the drape with the reduced fracture in the middle
   of the cast area (a little swelling and bruising). Steps:
     1 stockinette  drag the rolled stockinette along the limb: it unrolls behind the roll
     2 padding      drag the padding roll up over the limb (it goes round underneath by itself);
                    steer it sideways so each turn covers half of the last (teal guide)
     3 dip          pick the plaster roll up, hold it under the water until the bubbles stop, let go
     4 plaster      the same spiral wrap, up the limb and back (2 anchor turns at each end), until
                    every part has layersMin…layersMax layers
     5 mould        hold LMB and rub the cast with the palm (working-time timer) until the mould
                    meter is in the green band; then hands off while it sets (a press = a crack)
     6 fold         drag each stockinette end in over the edge of the cast
     7 cms          press the skin past the cast, let go: capillary refill, then motor / sensation
   Step away  P / "Step away" on the procedure HUD (core ProcPanel opts.pause, on once the scene is up, off
              on the result): snapshot() goes to Lua ('_proc:pause'), the server parks the session for
              Config.ProcPause.keep and the app closes. Using "Apply cast" on the same fracture again opens it
              with data.resume = that snapshot and boot() → restore() rebuilds the same point on the fresh scene
              by running the game's own step machine through it (quietly: no sounds, notes or step timers):
                stockinette  how far it is rolled on
                padding /    the centre of every turn laid by hand (the anchor turns, the passes up and back
                plaster      and the end of the wrap follow from them as in play: each turn sits on the last,
                             so the layers, the overlap scores and the bands come back exactly), plus the turn
                             being rolled on (centre, how far up)
                dip          how soaked the roll is and whether it was left lying in the water
                mould        the mould of each of the 24 sections, the working time left, setting or not, how
                             far it has set, every crack (where it was pressed; drawn again the same)
                fold         each stockinette end folded or not
                cms          pressing (start again) or how far the refill check has run
              plus the step, the active time (minTime counts both parts) and the scene seed. Never the 3D
              meshes or thickness fields: those are rebuilt from the turns. null while a move is half done
              (a roll / cuff in the hand, rubbing, the plaster roll held, pressing the skin, the last check
              done and the result being saved): the HUD says to finish it first. Every field is checked: an
              unreadable or out-of-range one starts its own step over (a wrap that does not replay cleanly
              is taken off again), a step is entered only when the ones before it are done, and data of a
              step later than the one it was on is never read. A snapshot for another fracture (injury,
              region, scene seed) or an unreadable one starts fresh with a note; one that throws while it
              is rebuilt restarts the game cleanly (restartClean: a new scene, never a half-rebuilt one).
              Supplies: the open data counts none (the cast item is checked when it opens and taken on the
              finish; stockinette, padding and plaster come with it), so nothing can run out part-way.
   Lua → JS   open { injury, region, regionLabel, bone, boneLabel, castType, side, leg, layersMin,
              layersMax, name, upper, tone?, sex?, seed?, keys, locale, resume? } · result (server outcome)
              (client/modules/xray.lua RunApp copies every ctx.data field, data.resume with them, and
              closes the app when the session ends, also on a pause)
   JS → Lua   exactly the 2D posts: xray:finish { score, coverage, layersMin, layersMax, cracks, mould }
              · xray:abort {} (hold ESC) · '_proc:pause' { snapshot } (core, Step away). The finish is never
              posted before minTime (14 s) of active time.
   Preview    index.html?app=xray&mode=cast&stage=stockinette|padding|dip|plaster|mould|setting|fold|cms|done
              &site=forearm|arm|leg|thigh &tone=0..1 &sex=m|f &pass=0..2 &turns=0..3 &no3d=1 (2D fallback)
              &resume=stockinette|padding|dip|plaster|mould|setting|fold|cms: plays to a point in that step,
              steps away and opens again from the snapshot (P in the preview parks it, Reopen carries on)
   Debug      XrayCast3D.debug.state() → the running game's progress (emulator scenarios)
   Everything the engine lacks (stockinette tube + roll, padding / plaster bands that wrap the limb,
   rolls, water basin with bubbles and drips, moulded cast shell, gloved hands, folded cuffs) is built
   here with THREE on S.scene and freed with the scene (S.dispose + this file's own bin).
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA) return;
  const THREE = window.THREE;
  const TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const wrapA = a => ((((a + Math.PI) % TAU) + TAU) % TAU) - Math.PI;   // any angle → −π..π

  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };

  // per limb: band width (padding / plaster roll), cast length, stockinette past each end, view width, roll radius
  const LIMB = {
    lower_arm: { bw: 0.075, Lc: 0.15, ext: 0.03, view: 0.36, roll: 0.017 },
    upper_arm: { bw: 0.09, Lc: 0.18, ext: 0.032, view: 0.41, roll: 0.019 },
    lower_leg: { bw: 0.1, Lc: 0.2, ext: 0.035, view: 0.45, roll: 0.021 },
    upper_leg: { bw: 0.13, Lc: 0.26, ext: 0.04, view: 0.56, roll: 0.025 },
  };
  const TONES = [0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88];
  const A0 = 1.3;            // engine angle where every turn starts: the near side of the limb, in view
  const AFAR = -0.62;        // ... and where its visible pass ends: over the far top
  const PASS = A0 - AFAR;    // visible part of a turn (rad); the rest goes round underneath by itself
  const CATCH = 7;           // rad/s the roll catches up with the cursor
  const NSEG = 64, AC = 10;  // band mesh: segments per turn × across
  const RING_A = 72, RING_B = 18;
  const GC = 8;                                           // guide band: columns across
  const STK = 0.0007, PAD_TH = 0.0016, PL_TH = 0.0011;   // layer thickness (m)
  const DS = 0.0015, NA = 128;                            // thickness field cell (m) × angle cells
  const CELLS = 24;                                       // cast sections for the layer count (as the 2D game)
  const WORK_TIME = 32;                                   // s of working time to mould before the plaster sets
  const SET_TIME = 5;                                     // s to set (as the 2D game)
  const MOULD_TOUCH = 0.2;                               // every cast section needs at least this much moulding
  const MIN_TIME = 15;                                    // s: the server's minTime (14) + slack before the finish post
  const STEPS = ['stockinette', 'padding', 'dip', 'plaster', 'mould', 'fold', 'cms'];
  const STEP_ICON = { stockinette: 'bandage', padding: 'gauze', dip: 'drop', plaster: 'splint', mould: 'hand', fold: 'rot-l', cms: 'pulse' };
  // step away / carry on (see the header): readers that never trust a snapshot field
  const MAX_EL = 3600;                                    // s: the active time a snapshot may carry
  const MAX_TURNS = 120;                                  // hand-laid turns a wrap may carry
  const CMS_END = 4.4;                                    // s: the refill check is done here
  const num = (v, fb) => { const n = Number(v); return v !== null && v !== '' && typeof v !== 'boolean' && typeof v !== 'object' && Number.isFinite(n) ? n : fb; };
  const rnd = (v, k) => { const m = Math.pow(10, k); return Math.round((+v || 0) * m) / m; };
  const bit = v => (v === 1 || v === true ? 1 : v === 0 || v === false ? 0 : -1);
  const intIn = (v, lo, hi) => { const n = num(v, NaN); return Number.isInteger(n) && n >= lo && n <= hi ? n : null; };
  const numIn = (v, lo, hi) => { const n = num(v, NaN); return n >= lo && n <= hi ? n : null; };
  const plain = v => !!v && typeof v === 'object' && !Array.isArray(v);
  // a list (an empty one may come back from Lua as {})
  const list = v => (Array.isArray(v) ? v : plain(v) && !Object.keys(v).length ? [] : null);
  let PARKED = null;            // preview: the snapshot "Step away" kept (Reopen carries on from it)
  let PREVIEW_MOCKED = false;   // preview: the '_proc:pause' mock is installed once (a test may replace it)
  let PREVIEW_PARKED = false;   // preview: ?resume=<stage> runs once per page
  let NEXT_NOTE = null;         // the note the next game opens with (a snapshot that could not be rebuilt)

  /* ═════════════════════════════ CSS (stage, cursor ring, loading veil) ═════════════════════════════ */
  const CSS = `
#app-xray .xc3-stage{position:absolute;inset:0;overflow:hidden;cursor:crosshair;pointer-events:auto;background:#050607}
#app-xray .xc3-stage.grab{cursor:grab}
#app-xray .xc3-stage.grabbing{cursor:grabbing}
#app-xray .xc3-stage.hide{cursor:none}
#app-xray .xc3-stage.point{cursor:pointer}
#app-xray .xc3-cur{position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;opacity:0;transition:opacity 140ms;z-index:5}
#app-xray .xc3-cur.on{opacity:1}
#app-xray .xc3-cur svg{position:absolute;left:-23px;top:-23px;width:46px;height:46px;transform:rotate(-90deg)}
#app-xray .xc3-cur.noring svg{display:none}
#app-xray .xc3-cur .bg{stroke:rgba(255,255,255,.22);fill:none;stroke-width:3}
#app-xray .xc3-cur .fg{stroke:var(--teal-hi);fill:none;stroke-width:3;stroke-linecap:round;filter:drop-shadow(0 0 4px rgba(15,212,196,.7))}
#app-xray .xc3-cur.red .fg{stroke:#ff7478;filter:drop-shadow(0 0 4px rgba(229,72,77,.7))}
#app-xray .xc3-cur.amber .fg{stroke:#f3c35a;filter:drop-shadow(0 0 4px rgba(229,165,10,.6))}
#app-xray .xc3-cur .tx{position:absolute;left:30px;top:-11px;height:22px;display:inline-flex;align-items:center;padding:0 8px;border-radius:6px;white-space:nowrap;
  font:600 11px var(--font);color:var(--white);background:rgba(12,13,16,.86);border:1px solid var(--hud-line)}
#app-xray .xc3-cur.noring .tx{left:16px}
#app-xray .xc3-cur .tx:empty{display:none}
#app-xray .xc3-cur.teal .tx{color:var(--teal-hi)} #app-xray .xc3-cur.red .tx{color:#ff9a9d} #app-xray .xc3-cur.amber .tx{color:#f3c35a}
#app-xray .xc3-load{position:absolute;inset:0;display:grid;place-items:center;background:#050607;transition:opacity 260ms;pointer-events:none;z-index:4}
#app-xray .xc3-load.out{opacity:0}
#app-xray .xc3-load .in{display:flex;flex-direction:column;align-items:center;gap:12px;color:var(--ink-3);font-size:12px}
#app-xray .xc3-load .ring{width:34px;height:34px;border-radius:50%;border:3px solid rgba(255,255,255,.1);border-top-color:var(--teal);animation:xc3-spin 900ms linear infinite}
@keyframes xc3-spin{to{transform:rotate(360deg)}}`;
  function injectCss() {
    if (document.getElementById('xc3-css')) return;
    const s = document.createElement('style');
    s.id = 'xc3-css'; s.textContent = CSS;
    document.head.appendChild(s);
  }
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

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
  // cotton stockinette: jersey knit, columns of V loops along the tube (u = around, v = along)
  function knitTex() {
    if (TEX.knit) return TEX.knit;
    const n = 128, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(41);
    x.fillStyle = '#404040'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#e7e1d4'; ax.fillRect(0, 0, n, n);
    const W = 16, C = 22, cw = n / W, ch = n / C;
    for (let i = 0; i < W; i++) {
      for (let j = 0; j < C; j++) {
        const cx = (i + 0.5) * cw, cy = j * ch, v = 170 + r() * 60;
        x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = cw * 0.36; x.lineCap = 'round';
        x.beginPath(); x.moveTo(cx - cw * 0.3, cy); x.lineTo(cx, cy + ch * 1.05); x.lineTo(cx + cw * 0.3, cy); x.stroke();
        const av = 238 + r() * 12;
        ax.strokeStyle = `rgba(${av},${av - 3},${av - 10},0.75)`; ax.lineWidth = cw * 0.3; ax.lineCap = 'round';
        ax.beginPath(); ax.moveTo(cx - cw * 0.3, cy); ax.lineTo(cx, cy + ch * 1.05); ax.lineTo(cx + cw * 0.3, cy); ax.stroke();
      }
    }
    for (let i = 0; i < 260; i++) { const sx = r() * n, sy = r() * n, L = 2 + r() * 5, g = r() * TAU; ax.strokeStyle = `rgba(255,252,244,${0.1 + r() * 0.2})`; ax.lineWidth = 0.6; ax.beginPath(); ax.moveTo(sx, sy); ax.lineTo(sx + Math.cos(g) * L, sy + Math.sin(g) * L); ax.stroke(); }
    TEX.knit = { albedo: a, normal: heightToNormal(h, 2.2) };
    return TEX.knit;
  }
  // undercast padding: soft white non-woven fibre with faint crimp lines across the roll
  function paddingTex() {
    if (TEX.pad) return TEX.pad;
    const n = 256, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(87);
    x.fillStyle = '#7a7a7a'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#f2f1ec'; ax.fillRect(0, 0, n, n);
    // cloudy fibre clumps
    for (let i = 0; i < 520; i++) {
      const cx = r() * n, cy = r() * n, rr = 3 + r() * 12, v = 100 + r() * 90;
      const g = x.createRadialGradient(cx, cy, 0, cx, cy, rr); g.addColorStop(0, `rgba(${v},${v},${v},0.5)`); g.addColorStop(1, `rgba(${v},${v},${v},0)`);
      x.fillStyle = g; x.fillRect(cx - rr, cy - rr, rr * 2, rr * 2);
      const av = 228 + r() * 26, ga = ax.createRadialGradient(cx, cy, 0, cx, cy, rr); ga.addColorStop(0, `rgba(${av},${av - 1},${av - 6},0.4)`); ga.addColorStop(1, `rgba(${av},${av},${av},0)`);
      ax.fillStyle = ga; ax.fillRect(cx - rr, cy - rr, rr * 2, rr * 2);
    }
    // fibres
    for (let i = 0; i < 1400; i++) {
      const sx = r() * n, sy = r() * n, L = 3 + r() * 14, g = r() * TAU, v = 150 + r() * 100;
      x.strokeStyle = `rgba(${v},${v},${v},0.35)`; x.lineWidth = 0.7; x.beginPath(); x.moveTo(sx, sy); x.quadraticCurveTo(sx + Math.cos(g + 0.5) * L * 0.5, sy + Math.sin(g + 0.5) * L * 0.5, sx + Math.cos(g) * L, sy + Math.sin(g) * L); x.stroke();
      ax.strokeStyle = `rgba(255,255,252,${0.12 + r() * 0.2})`; ax.lineWidth = 0.6; ax.beginPath(); ax.moveTo(sx, sy); ax.lineTo(sx + Math.cos(g) * L, sy + Math.sin(g) * L); ax.stroke();
    }
    // crimp lines across (along the band's width)
    for (let k = 0; k < 18; k++) { const y0 = (k + 0.5) * n / 18; x.strokeStyle = 'rgba(70,70,70,0.25)'; x.lineWidth = 2.2; x.beginPath(); x.moveTo(y0, 0); for (let i = 1; i <= 16; i++) x.lineTo(y0 + Math.sin(i * 0.9 + k) * 1.5, (i / 16) * n); x.stroke(); }
    TEX.pad = { albedo: a, normal: heightToNormal(h, 2.0) };
    return TEX.pad;
  }
  // plaster of Paris bandage: an open leno gauze (threads ≈ 1.5 mm apart) loaded with chalky plaster
  function plasterTex() {
    if (TEX.pl) return TEX.pl;
    const n = 256, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(133);
    x.fillStyle = '#6c6c6c'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#ece9e2'; ax.fillRect(0, 0, n, n);
    const N = 22, step = n / N;
    for (const dir of [0, 1]) {
      for (let k = 0; k < N; k++) {
        const off = (k + 0.5) * step, v = 170 + r() * 60;
        x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = step * 0.34;
        const av = 246 + r() * 8;
        ax.strokeStyle = `rgba(${av},${av - 1},${av - 5},0.7)`; ax.lineWidth = step * 0.28;
        x.beginPath(); ax.beginPath();
        for (let i = 0; i <= 22; i++) {
          const p = (i / 22) * n, wv = Math.sin((i / 22) * TAU * 3 + k * 1.3) * 0.6;
          const X = dir ? p : off + wv, Y = dir ? off + wv : p;
          if (i) { x.lineTo(X, Y); ax.lineTo(X, Y); } else { x.moveTo(X, Y); ax.moveTo(X, Y); }
        }
        x.stroke(); ax.stroke();
      }
    }
    // plaster filling the holes in patches + chalk speckle
    for (let i = 0; i < 700; i++) {
      const cx = r() * n, cy = r() * n, rr = 2 + r() * 9, v = 120 + r() * 80;
      const g = x.createRadialGradient(cx, cy, 0, cx, cy, rr); g.addColorStop(0, `rgba(${v},${v},${v},0.55)`); g.addColorStop(1, `rgba(${v},${v},${v},0)`);
      x.fillStyle = g; x.fillRect(cx - rr, cy - rr, rr * 2, rr * 2);
      const av = 232 + r() * 20; ax.fillStyle = `rgba(${av},${av - 2},${av - 7},${0.15 + r() * 0.25})`; ax.beginPath(); ax.arc(cx, cy, rr * 0.6, 0, TAU); ax.fill();
    }
    TEX.pl = { albedo: a, normal: heightToNormal(h, 2.4) };
    return TEX.pl;
  }
  // the end of a roll: tight concentric layers
  function rollEndTex(base) {
    const key = `end${base}`;
    if (TEX[key]) return TEX[key];
    const n = 128, c = cvs(n, n), x = c.getContext('2d'), r = rng(base.length * 7);
    x.fillStyle = base; x.fillRect(0, 0, n, n);
    for (let k = 4; k < 64; k += 1.6 + r() * 1.2) { x.strokeStyle = `rgba(0,0,0,${0.06 + r() * 0.08})`; x.lineWidth = 0.8; x.beginPath(); x.arc(64, 64, k, 0, TAU); x.stroke(); }
    TEX[key] = c;
    return c;
  }
  // nitrile glove grain
  function gloveTex() {
    if (TEX.glove) return TEX.glove;
    const n = 256, c = cvs(n, n), x = c.getContext('2d'), r = rng(91);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < 5200; i++) { const v = 100 + r() * 70; x.fillStyle = `rgb(${v},${v},${v})`; x.beginPath(); x.arc(r() * n, r() * n, 0.6 + r() * 1.1, 0, TAU); x.fill(); }
    TEX.glove = heightToNormal(c, 2.2);
    return TEX.glove;
  }
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
  // water ripples (tileable)
  function rippleTex() {
    if (TEX.ripple) return TEX.ripple;
    const n = 128, h = cvs(n, n), x = h.getContext('2d'), r = rng(17);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < 90; i++) {
      const cx = r() * n, cy = r() * n, rr = 6 + r() * 26, v = r() < 0.5 ? 60 : 200;
      for (const ox of [-n, 0, n]) for (const oy of [-n, 0, n]) {
        const g = x.createRadialGradient(cx + ox, cy + oy, 0, cx + ox, cy + oy, rr); g.addColorStop(0, `rgba(${v},${v},${v},0.22)`); g.addColorStop(1, `rgba(${v},${v},${v},0)`);
        x.fillStyle = g; x.fillRect(cx + ox - rr, cy + oy - rr, rr * 2, rr * 2);
      }
    }
    TEX.ripple = heightToNormal(h, 3.5);
    return TEX.ripple;
  }
  // ghost guide band: bright dashed edges, a faint fill (u along, v across)
  function guideTex() {
    if (TEX.guide) return TEX.guide;
    const W = 256, H = 64, c = cvs(W, H), x = c.getContext('2d');
    const g = x.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, 'rgba(255,255,255,0.0)'); g.addColorStop(0.08, 'rgba(255,255,255,0.45)'); g.addColorStop(0.16, 'rgba(255,255,255,0.12)');
    g.addColorStop(0.84, 'rgba(255,255,255,0.12)'); g.addColorStop(0.92, 'rgba(255,255,255,0.45)'); g.addColorStop(1, 'rgba(255,255,255,0.0)');
    x.fillStyle = g; x.fillRect(0, 0, W, H);
    x.fillStyle = 'rgba(255,255,255,1)';
    for (let i = 0; i < 8; i++) { x.fillRect(i * 32, 3, 18, 3); x.fillRect(i * 32, H - 6, 18, 3); }
    TEX.guide = c;
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
  // a regular grid (cols × rows quads) with uv 0..1; positions filled by the caller.
  // flip: the other winding (a grid whose columns run round the limb and rows along it faces inward
  // otherwise, and a DoubleSide material would then light its outside as a back face)
  function gridGeo(cols, rows, flip) {
    const nv = (cols + 1) * (rows + 1);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(nv * 3), 3).setUsage(THREE.DynamicDrawUsage));
    const uv = new Float32Array(nv * 2);
    for (let j = 0; j <= rows; j++) for (let i = 0; i <= cols; i++) { const k = j * (cols + 1) + i; uv[k * 2] = i / cols; uv[k * 2 + 1] = 1 - j / rows; }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2).setUsage(THREE.DynamicDrawUsage));
    const idx = [];
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) { const a = j * (cols + 1) + i, b = a + 1, c = a + cols + 1, d = c + 1; if (flip) idx.push(a, b, c, b, d, c); else idx.push(a, c, b, b, c, d); }
    g.setIndex(idx);
    return g;
  }
  // grid normals from neighbour differences, flipped to agree with outFn(k) (an outward hint); rows j0..j1
  function gridNormals(g, cols, rows, outFn, j0 = 0, j1 = rows) {
    const p = g.attributes.position.array, n = g.attributes.normal.array, W1 = cols + 1;
    for (let j = j0; j <= j1; j++) {
      for (let i = 0; i <= cols; i++) {
        const k = j * W1 + i, l = j * W1 + Math.max(0, i - 1), r = j * W1 + Math.min(cols, i + 1), u = Math.max(0, j - 1) * W1 + i, d = Math.min(rows, j + 1) * W1 + i;
        const ax = p[r * 3] - p[l * 3], ay = p[r * 3 + 1] - p[l * 3 + 1], az = p[r * 3 + 2] - p[l * 3 + 2];
        const bx = p[d * 3] - p[u * 3], by = p[d * 3 + 1] - p[u * 3 + 1], bz = p[d * 3 + 2] - p[u * 3 + 2];
        let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
        const L = Math.hypot(nx, ny, nz), o = outFn(k);
        // a collapsed quad (rows squeezed onto one line) has no normal of its own: take the hint
        if (L < 1e-10) { nx = o[0]; ny = o[1]; nz = o[2]; } else { nx /= L; ny /= L; nz /= L; }
        if (nx * o[0] + ny * o[1] + nz * o[2] < 0) { nx = -nx; ny = -ny; nz = -nz; }
        n[k * 3] = nx; n[k * 3 + 1] = ny; n[k * 3 + 2] = nz;
      }
    }
    g.attributes.position.needsUpdate = true; g.attributes.normal.needsUpdate = true;
  }

  /* ═════════════════════════════ gloved hand (from the bleed close-up) ═════════════════════════════
     Tool frame: origin at the contact point, +Y toward the wrist, back of the hand +Z, palm −Z,
     thumb on +X. mould = palm on the cast, fingers curled over it · point = index finger out */
  const HAND_POSE = {
    // the fingers follow the round of the cast (≈1.3 rad over their length), the thumb lies along its side
    // (flat hand, fingers together, the thumb laid along the side of the index: how a cast is moulded)
    mould: { flex: [[0.3, 0.42, 0.28], [0.28, 0.42, 0.28], [0.3, 0.44, 0.28], [0.34, 0.46, 0.3]], thumb: [0.12, 0.16, 0.1], thumbDir: [0.34, -0.86, -0.38], wrist: 0.42, contact: 'palm', box: 0.68 },
    point: { flex: [[0.06, 0.05, 0.02], [1.2, 1.35, 0.7], [1.25, 1.4, 0.72], [1.3, 1.4, 0.72]], thumb: [0.85, 0.65, 0.5], thumbDir: [0.5, -0.66, -0.5], wrist: 0.12, contact: 'index' },
  };
  // opt.bendR (m): the hand wraps a cylinder of that radius (the cast) round its contact point: the palm,
  // the finger and thumb bases and the wrist mount drop by the sagitta y²/2R from where they lie flat
  function buildHand(M, keep, poseName, scale, opt = {}) {
    const Rl = opt.bendR ? opt.bendR / (scale || 0.86) : 0;
    const bend = y => (Rl ? Math.pow(y - 0.03, 2) / (2 * Rl) : 0);
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
        const sq = v => Math.sign(v) * Math.pow(Math.abs(v), P.box || 0.84);
        x = sq(x) * w / 2; y = sq(y) * l / 2; zz = sq(zz) * t / 2;
        const fy = clamp((y + l / 2) / l, 0, 1);
        const k = lerp(1, 0.78, fy) * (1 - 0.06 * Math.pow(Math.abs(y) / (l / 2), 3));
        x *= k;
        if (zz > 0) zz *= lerp(0.74, 1, smooth(0, 0.34, fy));
        zz += (1 - Math.pow(x / (w / 2), 2)) * t * 0.07 * (zz > 0 ? 1 : 0.25);
        if (zz > 0) zz += 0.0022 * Math.exp(-Math.pow((y + l / 2 - 0.006) / 0.008, 2));
        // the mould palm cups a little round the cast
        zz -= bend(y + 0.046);
        p.setXYZ(i, x, y, zz);
      }
      palmG.computeVertexNormals();
    }
    const palm = new THREE.Mesh(palmG, M.glove);
    palm.position.set(-0.001, 0.046, 0);
    inner.add(palm);
    const blobG = keep(new THREE.SphereGeometry(1, 28, 18));
    const thenar = new THREE.Mesh(blobG, M.glove);
    thenar.scale.set(0.017, 0.03, 0.011); thenar.position.set(0.026, 0.066, -0.008 - bend(0.066)); thenar.rotation.z = -0.35;
    inner.add(thenar);
    const hypo = new THREE.Mesh(blobG, M.glove);
    hypo.scale.set(0.014, 0.034, 0.009); hypo.position.set(-0.03, 0.06, -0.007 - bend(0.06));
    inner.add(hypo);
    FINGERS.forEach((f, fi) => {
      const flex = P.flex[fi], sp = f.splay;
      const dir = th => V3(Math.sin(sp) * Math.cos(th), -Math.cos(sp) * Math.cos(th), -Math.sin(th));
      const pts = [V3(f.x - Math.sin(sp) * 0.024, 0.024, -0.0015 - bend(0.024))];
      let cur = V3(f.x, 0, -bend(0)), th = 0, acc = 0;
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
      const fl = P.thumb, base = V3(0.03, 0.07, -0.012 - bend(0.07)), d0 = V3(...P.thumbDir).normalize();
      const turn = (v, a) => V3(v.x * Math.cos(a) + v.y * Math.sin(a) * 0.35, v.y * Math.cos(a) - v.x * Math.sin(a) * 0.35, v.z - Math.sin(a) * 0.55).normalize();
      const p1 = base.clone().addScaledVector(turn(d0, fl[0] * 0.4), 0.032);
      const p2 = p1.clone().addScaledVector(turn(d0, fl[0] * 0.4 + fl[1]), 0.027);
      const p3 = p2.clone().addScaledVector(turn(d0, fl[0] * 0.4 + fl[1] + fl[2]), 0.022);
      const pts = [base.clone().addScaledVector(d0, -0.012), base, base.clone().lerp(p1, 0.5), p1, p1.clone().lerp(p2, 0.5), p2, p3];
      inner.add(new THREE.Mesh(keep(sweepGeo(pts, t => { const r = 0.0102 * lerp(1.06, 0.84, t); return { w: r * 1.05, h: r * 0.88, e: 2.2, pad: 0.05 }; }, { seg: 26, rad: 16, up: V3(0.5, 0, 1), capEnd: true, capLen: 0.9 })), M.glove));
    }
    const wrist = new THREE.Group();
    wrist.position.set(-0.002, 0.086, 0.001 - bend(0.086)); wrist.rotation.x = P.wrist;
    inner.add(wrist);
    wrist.add(new THREE.Mesh(keep(sweepGeo([V3(0, 0.002, 0), V3(0, 0.034, 0.001), V3(0, 0.082, 0.002)], t => ({ w: lerp(0.035, 0.031, t), h: lerp(0.016, 0.021, t), e: 2.3 }), { seg: 10, rad: 24 })), M.glove));
    const cuff = new THREE.Mesh(keep(new THREE.TorusGeometry(0.033, 0.0034, 10, 36)), M.glove);
    cuff.rotation.x = Math.PI / 2; cuff.scale.set(1, 0.68, 1); cuff.position.set(0, 0.082, 0.002); wrist.add(cuff);
    const knit = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.036, 0.035, 0.03, 32, 1, true)), M.sleeve);
    knit.scale.set(1, 1, 0.72); knit.position.set(0, 0.104, 0.002); wrist.add(knit);
    const slv = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.054, 0.038, 0.3, 32, 1, false)), M.sleeve);
    slv.scale.set(1, 1, 0.8); slv.position.set(0, 0.264, 0.005); wrist.add(slv);
    inner.updateMatrixWorld(true);
    const c = P.contact === 'index' ? pads[0].getWorldPosition(V3(0, 0, 0)) : V3(0, 0.03, -0.014);
    const SC = scale || 0.86;
    inner.scale.setScalar(SC);
    inner.position.copy(c).multiplyScalar(-SC);
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    g.visible = false;
    return { group: g, inner, base: inner.position.clone() };
  }

  /* ═════════════════════════════ preview data (browser only) ═════════════════════════════ */
  const SITES = {
    forearm: ['r_lower_arm', 'Right forearm', 'radius', 'Radius', 'short_arm', false],
    arm: ['l_upper_arm', 'Left upper arm', 'humerus', 'Humerus', 'long_arm', false],
    leg: ['r_lower_leg', 'Right lower leg', 'tibia', 'Tibia', 'short_leg', true],
    thigh: ['l_upper_leg', 'Left thigh', 'femur', 'Femur', 'long_leg', true],
  };
  function previewTweak(d) {
    if (NZA.inGame) return;
    const q = new URLSearchParams(location.search);
    const s = SITES[q.get('site')];
    if (s) Object.assign(d, { region: s[0], regionLabel: s[1], bone: s[2], boneLabel: s[3], castType: s[4], leg: s[5], upper: /upper/.test(s[0]) });
    if (q.get('tone') !== null) d.tone = clamp(+q.get('tone') || 0, 0, 1);
    if (q.get('sex')) d.sex = q.get('sex') === 'f' ? 'f' : 'm';
    // "Step away" in the browser: keep the snapshot and close; Reopen carries on from it (in game: the
    // same option on the same fracture within Config.ProcPause.keep). A test may replace this mock.
    if (!PREVIEW_MOCKED) {
      PREVIEW_MOCKED = true;
      NZA.mock('_proc:pause', r => { PARKED = r && r.snapshot; setTimeout(() => NZA.close('xray'), 80); return { ok: true }; });
    }
    if (PARKED && d.resume === undefined) { d.resume = PARKED; PARKED = null; }
  }

  /* ═════════════════════════════ materials ═════════════════════════════ */
  function materials(keep) {
    const tex = (c, srgb, rep) => { const t = keep(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; if (srgb) t.encoding = THREE.sRGBEncoding; if (rep) t.repeat.set(rep[0], rep[1]); return t; };
    const kn = knitTex(), pd = paddingTex(), pl = plasterTex();
    const M = {
      glove: keep(new THREE.MeshPhysicalMaterial({ color: 0x1f35a0, roughness: 0.5, normalMap: tex(gloveTex(), false, [2, 2]), normalScale: new THREE.Vector2(0.32, 0.32), sheen: 0.14, sheenRoughness: 0.55, sheenColor: new THREE.Color(0x4a62c0), clearcoat: 0.22, clearcoatRoughness: 0.42, envMapIntensity: 0.7 })),
      sleeve: keep(new THREE.MeshPhysicalMaterial({ color: 0x1d3a4a, roughness: 0.9, normalMap: tex(twillTex(), false, [3, 3]), normalScale: new THREE.Vector2(0.6, 0.6), sheen: 0.5, sheenColor: new THREE.Color(0x6aa4b4) })),
      knit: keep(new THREE.MeshPhysicalMaterial({ map: tex(kn.albedo, true), normalMap: tex(kn.normal, false), normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.95, sheen: 0.5, sheenRoughness: 0.6, sheenColor: new THREE.Color(1, 0.98, 0.94), side: THREE.DoubleSide })),
      knitRoll: keep(new THREE.MeshPhysicalMaterial({ map: tex(kn.albedo, true), normalMap: tex(kn.normal, false), normalScale: new THREE.Vector2(1.1, 1.1), color: 0xf0ece4, roughness: 0.96, sheen: 0.3, sheenRoughness: 0.7, sheenColor: new THREE.Color(1, 0.98, 0.94) })),
      padding: keep(new THREE.MeshPhysicalMaterial({ map: tex(pd.albedo, true), normalMap: tex(pd.normal, false), normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.98, sheen: 0.55, sheenRoughness: 0.8, sheenColor: new THREE.Color(1, 1, 1), side: THREE.DoubleSide })),
      padRoll: keep(new THREE.MeshPhysicalMaterial({ map: tex(pd.albedo, true), normalMap: tex(pd.normal, false), normalScale: new THREE.Vector2(1, 1), roughness: 0.98, sheen: 0.2, sheenColor: new THREE.Color(1, 1, 1) })),
      // plaster: wet (glossy slurry) → set (matte chalk); the turns and the moulded shell share it
      plaster: keep(new THREE.MeshPhysicalMaterial({ map: tex(pl.albedo, true), normalMap: tex(pl.normal, false), normalScale: new THREE.Vector2(0.75, 0.75), color: 0xdcdad3, roughness: 0.5, clearcoat: 0.55, clearcoatRoughness: 0.32, side: THREE.DoubleSide })),
      plasterDry: keep(new THREE.MeshPhysicalMaterial({ map: tex(pl.albedo, true), normalMap: tex(pl.normal, false), normalScale: new THREE.Vector2(1, 1), color: 0xf6f4ee, roughness: 0.95 })),
      padEnd: keep(new THREE.MeshStandardMaterial({ map: tex(rollEndTex('#efede6'), true), roughness: 0.95 })),
      plEnd: keep(new THREE.MeshStandardMaterial({ map: tex(rollEndTex('#ebe8e0'), true), roughness: 0.9 })),
      core: keep(new THREE.MeshStandardMaterial({ color: 0x9a8f80, roughness: 0.8 })),
      coreWhite: keep(new THREE.MeshPhysicalMaterial({ color: 0xe9eef0, roughness: 0.4, clearcoat: 0.3 })),
      // brushed stainless basin; the water is mostly see-through (a faint tint, reflections, ripples)
      basin: keep(new THREE.MeshPhysicalMaterial({ color: 0xbfc6cc, metalness: 0.85, roughness: 0.3, clearcoat: 0.25, clearcoatRoughness: 0.4, envMapIntensity: 1.1, side: THREE.DoubleSide })),
      // (no clearcoat: water reflects little looking down into it; the tint and the ripples read as water)
      water: keep(new THREE.MeshPhysicalMaterial({ color: 0x3f7a88, roughness: 0.06, metalness: 0, transparent: true, opacity: 0.58, normalMap: tex(rippleTex(), false, [3, 3]), normalScale: new THREE.Vector2(0.35, 0.35), envMapIntensity: 0.9, depthWrite: false })),
      meniscus: keep(new THREE.MeshBasicMaterial({ color: 0xe8f4f6, transparent: true, opacity: 0.4, depthWrite: false, side: THREE.DoubleSide })),
      bubble: keep(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.05, transparent: true, opacity: 0.55, clearcoat: 1, envMapIntensity: 1.5, depthWrite: false })),
      drop: keep(new THREE.MeshPhysicalMaterial({ color: 0xe4eef0, roughness: 0.03, transparent: true, opacity: 0.8, clearcoat: 1, envMapIntensity: 1.6 })),
      guide: keep(new THREE.MeshBasicMaterial({ map: tex(guideTex(), false), color: 0x0fd4c4, transparent: true, opacity: 0.8, depthWrite: false, toneMapped: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 })),
      blanch: keep(new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.6, transparent: true, opacity: 0, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 })),
      crack: keep(new THREE.MeshBasicMaterial({ color: 0x5a564e, transparent: true, opacity: 0.85, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 })),
    };
    M.tex = tex;
    return M;
  }

  /* ═════════════════════════════ THE GAME ═════════════════════════════ */
  class Game {
    // ctx: { root, app (NZA.apps.xray), state (the app's S: .pp), d, post, sound, abortBtn, resultCard, fallback }
    // holder: { g } the app's mode handle reads (restartClean swaps the game in it)
    constructor(ctx, holder) {
      this.ctx = ctx; this.holder = holder || null; this.d = Object.assign({}, ctx.d);
      LOC = Object.assign({}, this.d.locale || {});
      previewTweak(this.d);
      const d = this.d;
      // carrying on after "Step away": data.resume (checked and rebuilt in boot → restore)
      this.hasResume = d.resume !== undefined && d.resume !== null;
      this.resumed = false; this.note = NEXT_NOTE; NEXT_NOTE = null;
      this.quiet = 0; this.restoring = false; this.crackList = [];
      // one function for the panel's "Step away" (a stable reference: pp.set only re-arms on a change)
      this.pauseFn = () => this.snapshot();
      this.key3 = String(d.region || (d.leg ? 'r_lower_leg' : 'r_lower_arm')).replace(/^[lr]_/, '');
      if (!LIMB[this.key3]) this.key3 = d.leg ? (d.upper ? 'upper_leg' : 'lower_leg') : (d.upper ? 'upper_arm' : 'lower_arm');
      this.L = LIMB[this.key3];
      this.leg = /leg/.test(this.key3);
      this.minL = +d.layersMin || 3; this.maxL = +d.layersMax || 6;
      this.castName = T(`cast_${d.castType || (this.leg ? 'short_leg' : 'short_arm')}`, this.leg ? 'Leg cast' : 'Arm cast');
      this.alive = true; this.ready = false; this.stepIdx = -1; this.t = 0; this.lmb = false; this.uiAt = 0;
      this.openAt = performance.now();
      this.cur = { p: null, text: '', tone: '' };
      this.res = { padQ: [], plQ: [], cracks: 0, mould: 0 };
      this.bin = new Set();
      const app = this.app = ctx.app, root = ctx.root;
      // the app shell: an opaque full-screen close-up, no game-camera input
      this.prevApp = { full: app.full, opaque: app.opaque, camInput: app.camInput };
      app.full = true; app.opaque = true; app.camInput = false;
      app.el.classList.add('nza-full');
      root.querySelectorAll('.xr-root').forEach(n => { n.style.display = 'none'; });
      injectCss();
      this.stage = el('div', 'xc3-stage');
      root.insertBefore(this.stage, root.firstChild);
      this.curEl = el('div', 'xc3-cur', '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>');
      root.appendChild(this.curEl);
      this.curFg = this.curEl.querySelector('.fg'); this.curTx = this.curEl.querySelector('.tx');
      this.loadEl = el('div', 'xc3-load', `<div class="in"><span class="ring"></span><span>${NZA.esc(T('c3_loading', 'Preparing the close-up…'))}</span></div>`);
      root.appendChild(this.loadEl);
      // the procedure HUD (the app's teardown destroys it through state.pp)
      this.pp = ctx.state.pp = NZA.ui.ProcPanel(root, {
        step: 1, total: STEPS.length, tag: `${T('tag_cast', 'Apply cast')} · ${d.regionLabel || ''}`.replace(/ · $/, ''), title: '', text: '',
        tools: [], stats: [], abort: ctx.abortBtn(), onAbort: () => this.abort(), onTool: k => this.pickTool(k),
      });
      this.onBlur = () => { if (this.lmb) this.up({ button: 0 }); };
      this.onResize = () => { this.zoom = 0; };
      window.addEventListener('blur', this.onBlur);
      window.addEventListener('resize', this.onResize);
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive) this.boot(); }));
    }
    keep(x) { if (x) this.bin.add(x); return x; }

    /* ─────────────── scene ─────────────── */
    boot() {
      const d = this.d, L = this.L;
      const name = d.name || '';
      const seed = (+d.seed || hash(`${d.injury || 'i'}:${name}`)) >>> 0;
      this.seed = seed;
      this.R0 = rng(seed);
      const tone = d.tone !== undefined && d.tone !== null && d.tone !== '' ? clamp(+d.tone || 0, 0, 1) : TONES[hash(name || d.injury || 'x') % TONES.length];
      const sex = d.sex === 'f' ? 'f' : 'm';
      const preset = { lower_arm: 0.04, upper_arm: 0.05, lower_leg: 0.055, upper_leg: 0.075 }[this.key3];
      const H = TAU * preset * 0.995;
      // 'medium' = what the in-game cap (Config.UI.quality3d 'auto') gives anyway: the preview shows the real look
      const opts = {
        tone, sex, seed, region: d.region || 'r_lower_leg', quality: 'medium', size: [1.0, H],
        work: [L.Lc + 2 * L.ext + 0.12, H],
        focus: { uv: [0.5, 0.5], size: [L.Lc + 2 * L.ext, 0.05], view: L.view },
      };
      let S;
      try { S = NZA3D.createScene(this.stage, opts); } catch (e) { console.error('[xray] cast 3D scene', e); return this.fail(); }
      this.S = S;
      this.R = S.shape.R;
      S.controls.limits.pitchMin = 0.5;
      // geometry along the limb: proximal = left (−s), distal = right (+s)
      this.sP = -L.Lc / 2; this.sD = L.Lc / 2;
      this.fs0 = this.sP - L.ext - 0.02; this.fs1 = this.sD + L.ext + 0.02;
      this.NSF = Math.ceil((this.fs1 - this.fs0) / DS);
      this.fPad = new Float32Array(this.NSF * NA);
      this.fPl = new Float32Array(this.NSF * NA);
      this.layers = new Float32Array(CELLS);
      this.padLayers = new Float32Array(CELLS);
      this.mouldM = new Float32Array(CELLS);
      this.ray = new THREE.Raycaster();
      try {
        this.M = materials(x => this.keep(x));
        // below the high tier the engine drops cloth sheen (a costly lobe on large white areas): so do we
        if (S.quality !== 'high') Object.values(this.M).forEach(m => { if (m && m.isMeshPhysicalMaterial && m.sheen > 0) m.sheen = 0; });
        this.makeLimb();
        this.makeStockinette();
        this.makeRolls();
        this.makeBasin();
        this.makeHands();
        this.makeGuide();
      } catch (e) { console.error('[xray] cast 3D build', e); return this.fail(); }
      this.prewarm();
      S.on('frame', (dt, render) => this.frame(dt, render !== false));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.on('pointer', () => { if (this.ready && this.ph && this.ph.pointer && !this.finished) this.ph.pointer(); });
      S.start();
      this.ready = true;
      // carrying on after "Step away" (data.resume): rebuild the saved point on this fresh scene. A snapshot
      // for another fracture or an unreadable one starts fresh with a note; one that cannot be rebuilt
      // restarts the game cleanly (never a half-rebuilt scene)
      let note = this.note;
      if (this.hasResume) {
        const snap = plain(d.resume) ? d.resume : null;
        const m = snap ? this.limbMatch(snap) : 'bad';
        if (m === 'same') {
          this.quiet += 1; this.restoring = true;
          try { this.restore(snap); this.resumed = true; } catch (e) {
            console.error('[xray] cast restore', e);
            this.quiet -= 1; this.restoring = false;
            return this.restartClean();
          }
          this.quiet -= 1; this.restoring = false;
        } else note = m;
      }
      if (!this.resumed) this.nextStep();
      this.pp.set({ pause: this.pauseFn });          // "Step away" (P): park the cast, carry on later
      if (this.resumed) this.flash('ok', T('c3_resume', 'Carrying on where you left off.'), 3200);
      else if (note) {
        this.flash('warn', note === 'bad' ? T('c3_resume_bad', 'Could not carry on from where you left off - this cast starts from the beginning.')
          : T('c3_resume_other', 'You stepped away from a different fracture - this one starts from the beginning.'), 4200);
      }
      this.noteShown = this.resumed ? 'resumed' : note || null;
      setTimeout(() => this.loadEl && this.loadEl.classList.add('out'), 140);
      // (a resumed game opens where it was: no preview jump on top of it)
      if (this.pendingJump && !this.resumed) { const j = this.pendingJump; this.pendingJump = null; this.jump(j); }
      this.pendingJump = null;
      // preview: ?resume=<stage> plays to a point in that step, steps away and carries on (once per page)
      const pr = !NZA.inGame && !this.hasResume && !PREVIEW_PARKED ? new URLSearchParams(location.search).get('resume') : null;
      if (pr) { PREVIEW_PARKED = true; setTimeout(() => { if (this.alive) this.previewPark(pr); }, 150); }
    }

    // 3D could not start after all: hand the session to the 2D game
    fail() {
      const ctx = this.ctx;
      this.dispose();
      if (this.pp && ctx.state.pp === this.pp) { try { this.pp.destroy(); } catch (e) { /* gone */ } }
      ctx.state.pp = null;
      if (ctx.fallback) ctx.fallback();
    }

    viewFor(step) {
      const L = this.L;
      if (step === 'dip') return Math.max(0.48, L.view * 1.1);
      if (step === 'cms') return L.view;
      if (step === 'stockinette') return L.view * 1.1;
      // a little wider while the palm is on it: the hand never fills the view
      if (step === 'mould') return L.view * 1.15;
      return L.view;
    }
    frameStep(step, instant) {
      const S = this.S, L = this.L, R = this.R;
      if (step === 'dip') {
        const b = this.basin;
        S.controls.frame(S.stToUv(b.x - b.rimR * 0.75, -R * 0.5), this.viewFor('dip'), { pitch: 0.4, instant: !!instant });
        return;
      }
      if (step === 'done') { S.controls.frame(S.stToUv(L.Lc * 0.24, R * 0.32), L.view * 1.05, { pitch: 1.05, instant: !!instant }); return; }
      if (step === 'cms') { S.controls.frame(S.stToUv(this.sD + L.ext * 0.6, R * 0.25), this.viewFor('cms'), { pitch: 1.1, instant: !!instant }); return; }
      if (step === 'stockinette') { S.controls.frame(S.stToUv(L.Lc * 0.02, R * 0.32), this.viewFor(step), { pitch: 0.98, instant: !!instant }); return; }
      // the cast area a little right of centre (the step column covers the lower left)
      S.controls.frame(S.stToUv(-L.Lc * 0.06, R * 0.32), this.viewFor(step), { pitch: step === 'mould' || step === 'fold' ? 1.08 : 0.98, instant: !!instant });
    }

    /* ─────────────── the limb: swelling + bruising over the reduced fracture ─────────────── */
    makeLimb() {
      const S = this.S, L = this.L, R0 = this.R0, R = this.R;
      if (S._cloth) S._cloth.material.color.setHex(0x3f7f88);
      this.sF = (R0() - 0.5) * L.Lc * 0.16;
      this.aF = 0.25 + (R0() - 0.5) * 0.4;
      this.bump = { s: this.sF, t: this.aF * R, r: Math.min(0.05, L.Lc * 0.24), h: 0.0022 };
      S.bumps.add({ uv: S.stToUv(this.bump.s, this.bump.t), radius: this.bump.r, height: this.bump.h });
      const at = (ds, da) => S.stToUv(this.sF + ds, (this.aF + da) * R);
      for (let k = 0; k < 7; k++) {
        S.layers.paint('bruise', at((R0() - 0.5) * 0.05, (R0() - 0.5) * 0.7), [0.014 + R0() * 0.016, 0.01 + R0() * 0.01], 0.05 + R0() * 0.05, { hardness: 0, grain: 0.35, grainScale: 80, angle: R0() * Math.PI });
      }
      // a faded marker line where the break is (the plaster room marks it on the film check)
      S.layers.paint('bruise', at(0, 0), [0.022, 0.015], 0.06, { hardness: 0, grain: 0.4, grainScale: 120 });
    }
    // skin height over the base cylinder (the swelling only: the cast area has no wounds)
    skinH(s, a) {
      const b = this.bump, dx = s - b.s, dy = a * this.R - b.t, d2 = dx * dx + dy * dy, r2 = b.r * b.r;
      if (d2 >= r2) return 0;
      const f = 1 - d2 / r2;
      return b.h * f * f;
    }
    // thickness fields: bilinear sample (s along, a around)
    fAt(F, s, a) {
      let x = (s - this.fs0) / DS - 0.5;
      if (x < 0 || x > this.NSF - 1) return 0;
      const x0 = Math.floor(x), tx = x - x0, x1 = Math.min(this.NSF - 1, x0 + 1);
      let y = (wrapA(a) + Math.PI) / TAU * NA - 0.5;
      const y0 = Math.floor(y), ty = y - y0, j0 = (y0 + NA) % NA, j1 = (y0 + 1) % NA;
      const v00 = F[x0 * NA + j0], v01 = F[x0 * NA + j1], v10 = F[x1 * NA + j0], v11 = F[x1 * NA + j1];
      return lerp(lerp(v00, v01, ty), lerp(v10, v11, ty), tx);
    }
    // radius of whatever lies at (s, a) right now (skin + stockinette + padding + plaster)
    under(s, a, noPl) {
      let r = this.R + this.skinH(s, a);
      if (this.stockOn && s >= this.stk.lo - 0.0005 && s <= this.stk.hi + 0.0005) r += STK;
      r += this.fAt(this.fPad, s, a);
      if (!noPl) r += this.plDisp ? this.plDisp(s, a) : this.fAt(this.fPl, s, a);
      return r;
    }
    cyl(s, a, r, out) { return (out || new THREE.Vector3()).set(s, r * Math.cos(a) - this.R, r * Math.sin(a)); }

    /* ─────────────── picking: the cursor ray against the limb ─────────────── */
    pointerRay() {
      const S = this.S;
      this.ray.setFromCamera({ x: S.pointer.x * 2 - 1, y: 1 - S.pointer.y * 2 }, S.camera);
      return this.ray.ray;
    }
    // the cursor ray against a cylinder of radius r round the limb axis → { s, a, point } | null
    pickCyl(r) {
      const ray = this.pointerRay(), O = ray.origin, D = ray.direction;
      const oy = O.y + this.R, oz = O.z, A = D.y * D.y + D.z * D.z, B = 2 * (oy * D.y + oz * D.z), C = oy * oy + oz * oz - r * r;
      const disc = B * B - 4 * A * C;
      if (A < 1e-9 || disc < 0) return null;
      const t = (-B - Math.sqrt(disc)) / (2 * A);
      if (t <= 0) return null;
      const p = O.clone().addScaledVector(D, t);
      return { s: p.x, a: Math.atan2(p.z, p.y + this.R), point: p };
    }
    // s of the point on the line along the limb at angle a, radius r, closest to the cursor ray
    sAtPointer(a, r) {
      const ray = this.pointerRay(), O = ray.origin, D = ray.direction;
      const qy = r * Math.cos(a) - this.R, qz = r * Math.sin(a);
      const w0x = O.x, w0y = O.y - qy, w0z = O.z - qz;
      const b = D.x, dd = D.x * w0x + D.y * w0y + D.z * w0z, den = 1 - b * b;
      if (den < 1e-6) return 0;
      return (w0x - b * dd) / den;
    }
    // the cursor ray against a horizontal plane at height y → Vector3 | null
    pickPlane(y) {
      const ray = this.pointerRay(), O = ray.origin, D = ray.direction;
      if (Math.abs(D.y) < 1e-6) return null;
      const t = (y - O.y) / D.y;
      if (t <= 0) return null;
      return O.clone().addScaledVector(D, t);
    }
    // screen px distance from the cursor to a world point
    pxTo(P) {
      const S = this.S, q = S.project(P);
      return Math.hypot((q.x - S.pointer.x) * window.innerWidth, (q.y - S.pointer.y) * window.innerHeight);
    }

    /* ─────────────── 1. stockinette: tube (3 parts: proximal cuff, middle, distal cuff) + the roll ─────────────── */
    makeStockinette() {
      const S = this.S, M = this.M, L = this.L, R = this.R;
      const s0 = this.sD + L.ext, sE = this.sP - L.ext;
      const sPe = this.sP - 0.008, sDe = this.sD + 0.008;
      const NAs = 56;
      const part = (a, b, rows) => {
        const geo = this.keep(gridGeo(NAs, rows, true));
        const mesh = new THREE.Mesh(geo, M.knit);
        mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false; mesh.visible = false;
        S.scene.add(mesh);
        // uv: u around (the knit columns run along the tube), v along
        const uv = geo.attributes.uv.array;
        for (let j = 0; j <= rows; j++) for (let i = 0; i <= NAs; i++) { const k = j * (NAs + 1) + i; uv[k * 2] = (i / NAs) * (TAU * R / 0.012); uv[k * 2 + 1] = (lerp(a, b, j / rows) - sE) / 0.012; }
        geo.attributes.uv.needsUpdate = true;
        return { a, b, rows, geo, mesh, fold: 0, o: a < this.sP ? -1 : 1 };
      };
      // (the cuffs get enough rows to bend round the rolled edge when they are folded back)
      const parts = [part(sE, sPe, 30), part(sPe, sDe, Math.ceil((sDe - sPe) / 0.004)), part(sDe, s0, 30)];
      // the rolled-up stockinette (a doughnut round the limb) + the hems at the open ends
      const ringMat = this.keep(M.knitRoll.clone());
      ringMat.map = this.keep(M.knitRoll.map.clone()); ringMat.map.needsUpdate = true;
      // a doughnut laid analytically every frame (ring radius = the limb, tube radius = what is left on the roll)
      const ring = new THREE.Mesh(this.keep(gridGeo(RING_A, RING_B, true)), ringMat);
      ring.castShadow = true; ring.receiveShadow = true; ring.visible = false; ring.frustumCulled = false;
      S.scene.add(ring);
      const hems = [0, 1].map(() => { const m = new THREE.Mesh(this.keep(new THREE.TorusGeometry(1, 0.0011, 8, 72)), M.knit); m.castShadow = true; m.visible = false; S.scene.add(m); return m; });
      this.stk = { s0, sE, sPe, sDe, ring: s0, target: s0, parts, ringMesh: ring, ringMat, hems, lo: s0, hi: s0, NAs, done: false };
      this.layStock();
    }
    // lay the tube from the roll to the distal end; the roll's thickness shrinks as it unrolls
    layStock() {
      const st = this.stk, R = this.R, NAs = st.NAs;
      const P = new THREE.Vector3();
      st.lo = st.ring; st.hi = st.s0;
      const prog = clamp((st.s0 - st.ring) / (st.s0 - st.sE), 0, 1);
      st.parts.forEach(pt => {
        if (pt.fold > 0) return this.layFold(pt);
        const pos = pt.geo.attributes.position.array;
        let any = false;
        for (let j = 0; j <= pt.rows; j++) {
          const s0 = lerp(pt.a, pt.b, j / pt.rows), s = Math.max(s0, st.ring);
          const bunch = st.done ? 0 : Math.exp(-(s - st.ring) / 0.012);
          if (s0 >= st.ring - 1e-4) any = true;
          for (let i = 0; i <= NAs; i++) {
            const a = (i / NAs) * TAU - Math.PI, k = j * (NAs + 1) + i;
            const r = this.R + this.skinH(s, a) + STK * 0.8 + (s0 < st.ring ? 0 : 0.0016 * bunch * (0.6 + 0.4 * Math.sin(a * 9 + s * 500)));
            this.cyl(s, a, r, P);
            pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
          }
        }
        gridNormals(pt.geo, NAs, pt.rows, k => { const a = ((k % (NAs + 1)) / NAs) * TAU - Math.PI; return [0, Math.cos(a), Math.sin(a)]; });
        pt.geo.computeBoundingSphere();
        pt.mesh.visible = any;
      });
      // the roll: a doughnut on the limb at the front of the tube
      const tr = lerp(0.0078, 0.0032, prog);
      const ring = st.ringMesh;
      ring.visible = !st.done;
      if (ring.visible) this.layRing(ring.geometry, st.ring - tr * 0.4, tr);
      st.ringMat.map.offset.set(0, -(st.s0 - st.ring) / 0.012);
      // hems at the open ends
      const hd = st.hems[0], hp = st.hems[1];
      hd.visible = true; hd.rotation.set(0, Math.PI / 2, 0); hd.scale.set(R + STK + 0.0004, R + STK + 0.0004, 1); hd.position.set(st.s0, -R, 0);
      hp.visible = st.done && !st.parts[0].fold;
      if (hp.visible) { hp.rotation.set(0, Math.PI / 2, 0); hp.scale.set(R + STK + 0.0004, R + STK + 0.0004, 1); hp.position.set(st.sE, -R, 0); }
    }
    // the rolled stockinette: a doughnut of knit round the limb at sC, tube radius tr (sits on the skin)
    layRing(geo, sC, tr) {
      const pos = geo.attributes.position.array, uv = geo.attributes.uv.array, P = new THREE.Vector3();
      for (let j = 0; j <= RING_B; j++) {
        const b = (j / RING_B) * TAU, cb = Math.cos(b), sb = Math.sin(b);
        for (let i = 0; i <= RING_A; i++) {
          const a = (i / RING_A) * TAU - Math.PI, k = j * (RING_A + 1) + i;
          const rm = this.R + this.skinH(sC, a) + STK + tr;
          this.cyl(sC + tr * sb, a, rm + tr * cb, P);
          pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
          uv[k * 2] = (i / RING_A) * (TAU * rm / 0.012); uv[k * 2 + 1] = (j / RING_B) * (TAU * tr / 0.012);
        }
      }
      geo.attributes.uv.needsUpdate = true;
      gridNormals(geo, RING_A, RING_B, k => {
        const i = k % (RING_A + 1), j = Math.floor(k / (RING_A + 1)), a = (i / RING_A) * TAU - Math.PI, b = (j / RING_B) * TAU;
        return [Math.sin(b), Math.cos(b) * Math.cos(a), Math.cos(b) * Math.sin(a)];
      });
      geo.computeBoundingSphere();
    }

    /* ─────────────── rolls: padding roll (wrap), plaster roll (dip + wrap) ─────────────── */
    makeRolls() {
      const S = this.S, M = this.M, L = this.L;
      const mk = (side, end, core, w) => {
        const g = new THREE.Group(), inner = new THREE.Group(); g.add(inner);
        const sideG = this.keep(new THREE.CylinderGeometry(1, 1, w, 48, 1, true).rotateZ(Math.PI / 2));
        { const u = sideG.attributes.uv; for (let i = 0; i < u.count; i++) u.setXY(i, u.getX(i) * 4, u.getY(i) * w / 0.03); }
        inner.add(new THREE.Mesh(sideG, side));
        inner.add(new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.99, 0.99, w * 0.995, 48, 1, false).rotateZ(Math.PI / 2)), end));
        g.add(new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.0065, 0.0065, w * 1.01, 20, 1, false).rotateZ(Math.PI / 2)), core));
        g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
        g.visible = false;
        S.scene.add(g);
        return { group: g, inner, r: L.roll, w };
      };
      this.padRoll = mk(M.padRoll, M.padEnd, M.core, L.bw * 0.97);
      this.plRoll = mk(M.plasterDry, M.plEnd, M.coreWhite, L.bw * 0.97);
      this.padRoll.r = L.roll * 1.05; this.plRoll.r = L.roll * 0.95;
    }
    setRoll(roll, P, spin, radius) {
      roll.group.position.copy(P);
      roll.group.rotation.set(spin, 0, 0);
      roll.inner.scale.set(1, radius, radius);
      roll.group.visible = true;
    }

    /* ─────────────── the water basin, bubbles, ripples and drips ─────────────── */
    makeBasin() {
      const S = this.S, M = this.M, L = this.L, R = this.R;
      const floor = S._cloth ? S._cloth.position.y : -R * 1.55;
      // on the far side of the limb, past the distal end of the cast: the dip view looks over the limb at it,
      // and the wrap views keep it in the background
      const rimR = clamp(0.074 + L.bw * 0.12, 0.08, 0.1), botR = rimR * 0.78, Hb = 0.07;
      const b = { x: this.sD + L.ext + rimR * 0.7, z: -(R + rimR + 0.016), floor, rimR, botR, H: Hb, waterY: floor + Hb * 0.68, milk: 0 };
      // lathe profile: outer wall up to a rolled rim, inner wall down to the floor
      const pr = [];
      pr.push(new THREE.Vector2(0.0001, 0.002), new THREE.Vector2(botR - 0.006, 0.002), new THREE.Vector2(botR, 0.006));
      for (let i = 0; i <= 6; i++) { const f = i / 6; pr.push(new THREE.Vector2(lerp(botR, rimR, f), 0.006 + f * (Hb - 0.012))); }
      for (let i = 0; i <= 8; i++) { const a = -Math.PI / 2 + (i / 8) * Math.PI; pr.push(new THREE.Vector2(rimR + 0.004 + Math.cos(a) * 0.004, Hb - 0.006 + 0.004 + Math.sin(a) * 0.004)); }
      for (let i = 0; i <= 6; i++) { const f = i / 6; pr.push(new THREE.Vector2(lerp(rimR - 0.003, botR - 0.004, f), Hb - 0.004 - f * (Hb - 0.012))); }
      pr.push(new THREE.Vector2(0.0001, 0.008));
      const bowl = new THREE.Mesh(this.keep(new THREE.LatheGeometry(pr, 64)), M.basin);
      bowl.castShadow = true; bowl.receiveShadow = true;
      bowl.position.set(b.x, floor, b.z);
      S.scene.add(bowl);
      const wr = lerp(botR - 0.004, rimR - 0.003, (b.waterY - floor - 0.008) / (Hb - 0.012));
      const water = new THREE.Mesh(this.keep(new THREE.CircleGeometry(wr, 64).rotateX(-Math.PI / 2)), M.water);
      water.position.set(b.x, b.waterY, b.z); water.renderOrder = 3;
      water.receiveShadow = true;
      S.scene.add(water);
      // the meniscus: a bright line where the water meets the wall
      const men = new THREE.Mesh(this.keep(new THREE.RingGeometry(wr - 0.0022, wr + 0.0004, 72).rotateX(-Math.PI / 2)), M.meniscus);
      men.position.set(b.x, b.waterY + 0.0003, b.z); men.renderOrder = 4;
      S.scene.add(men);
      b.bowl = bowl; b.water = water; b.wr = wr;
      // bubbles + ripples + drips (pools)
      const bub = new THREE.InstancedMesh(this.keep(new THREE.SphereGeometry(1, 10, 8)), M.bubble, 48);
      bub.count = 0; bub.frustumCulled = false; bub.renderOrder = 4;
      S.scene.add(bub);
      b.bub = bub; b.bubbles = [];
      const rip = [];
      for (let i = 0; i < 4; i++) {
        const m = new THREE.Mesh(this.keep(new THREE.RingGeometry(0.92, 1, 48).rotateX(-Math.PI / 2)), this.keep(new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0, depthWrite: false })));
        m.position.set(b.x, b.waterY + 0.0005, b.z); m.visible = false; m.renderOrder = 4;
        S.scene.add(m); rip.push({ m, t: 1 });
      }
      b.rip = rip;
      const drops = new THREE.InstancedMesh(this.keep(new THREE.SphereGeometry(1, 8, 6)), M.drop, 40);
      drops.count = 0; drops.frustumCulled = false;
      S.scene.add(drops);
      this.drips = { mesh: drops, list: [] };
      this.basin = b;
      // the dry plaster roll waits on the drape beside the basin
      const pr0 = this.plRoll;
      b.home = new THREE.Vector3(b.x - rimR - 0.055, floor + pr0.r + 0.002, b.z - 0.025);
      // dip hints: a teal ring on the drape round the dry roll (pick it up), one on the water (in here)
      const ringMat = this.keep(new THREE.MeshBasicMaterial({ color: 0x0fd4c4, transparent: true, opacity: 0.7, depthWrite: false, toneMapped: false, side: THREE.DoubleSide }));
      const mkRing = (rIn, rOut, segs) => { const m = new THREE.Mesh(this.keep(new THREE.RingGeometry(rIn, rOut, segs).rotateX(-Math.PI / 2)), ringMat); m.visible = false; m.renderOrder = 5; S.scene.add(m); return m; };
      b.pickRing = mkRing(1, 1.06, 64); b.pickRing.scale.set(pr0.w * 0.62, 1, pr0.r * 1.9); b.pickRing.position.set(b.home.x, floor + 0.004, b.home.z);
      b.dropRing = mkRing(0.86, 0.9, 72); b.dropRing.scale.setScalar(wr); b.dropRing.position.set(b.x, b.waterY + 0.001, b.z);
      b.ringMat = ringMat;
      this.setRoll(pr0, b.home, 0.3, pr0.r);
    }
    ripple(P, size) {
      const r = this.basin.rip.find(x => x.t >= 1) || this.basin.rip[0];
      r.t = 0; r.size = size || 0.03; r.m.position.set(P.x, this.basin.waterY + 0.0005, P.z); r.m.visible = true;
    }
    drip(P, n = 1) {
      const dl = this.drips.list;
      for (let i = 0; i < n && dl.length < 40; i++) dl.push({ p: P.clone().add(new THREE.Vector3((Math.random() - 0.5) * 0.02, -0.004, (Math.random() - 0.5) * 0.01)), v: new THREE.Vector3(0, -0.05 - Math.random() * 0.1, 0), r: 0.0014 + Math.random() * 0.0012 });
    }
    fluidTick(dt) {
      const b = this.basin, S = this.S;
      // bubbles rise and pop
      const bl = b.bubbles, m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3();
      for (let i = bl.length - 1; i >= 0; i--) {
        const x = bl[i];
        x.p.y += x.v * dt; x.p.x += Math.sin(this.t * 9 + x.ph) * 0.004 * dt; x.p.z += Math.cos(this.t * 7 + x.ph) * 0.004 * dt;
        if (x.p.y >= b.waterY - x.r * 0.5) { if (Math.random() < 0.35) this.ripple(x.p, 0.01 + x.r * 4); bl.splice(i, 1); }
      }
      b.bub.count = bl.length;
      bl.forEach((x, i) => { sc.setScalar(x.r); m4.compose(x.p, q, sc); b.bub.setMatrixAt(i, m4); });
      if (bl.length) b.bub.instanceMatrix.needsUpdate = true;
      b.rip.forEach(r => {
        if (r.t >= 1) { r.m.visible = false; return; }
        r.t = Math.min(1, r.t + dt / 0.9);
        const s = r.size * (0.3 + r.t * 1.6);
        r.m.scale.set(s, 1, s); r.m.material.opacity = 0.35 * (1 - r.t);
      });
      b.water.material.normalMap.offset.set(this.t * 0.012, this.t * 0.008);
      // plaster washed off the roll clouds the water a little
      if (b.milk > 0 && b.milkShown !== b.milk) { b.milkShown = b.milk; b.water.material.opacity = 0.58 + 0.2 * b.milk; b.water.material.color.setHex(0x3f7a88).lerp(new THREE.Color(0xd8dcd6), b.milk * 0.6); }
      b.water.material.normalScale.setScalar(0.3 + 0.5 * (b.stir || 0));
      b.stir = Math.max(0, (b.stir || 0) - dt * 0.8);
      // drips fall onto the drape / the limb
      const dl = this.drips.list, dm = this.drips.mesh;
      for (let i = dl.length - 1; i >= 0; i--) {
        const x = dl[i];
        x.v.y -= 9.8 * dt; x.p.addScaledVector(x.v, dt);
        const ry = x.p.y + this.R, rr = Math.hypot(ry, x.p.z);
        const onLimb = x.p.x > this.fs0 && x.p.x < this.fs1 && rr < this.under(x.p.x, Math.atan2(x.p.z, ry));
        if (x.p.y < b.floor + 0.002 || onLimb) dl.splice(i, 1);
      }
      dm.count = dl.length;
      dl.forEach((x, i) => { sc.set(x.r, x.r * (1 + Math.min(1.2, -x.v.y * 0.6)), x.r); m4.compose(x.p, q, sc); dm.setMatrixAt(i, m4); });
      if (dl.length) dm.instanceMatrix.needsUpdate = true;
      void S;
    }

    /* ─────────────── hands, guide ─────────────── */
    makeHands() {
      const S = this.S, M = this.M;
      const sc = this.leg ? 0.82 : 0.74;
      // the mould hand is shaped round the cast (limb + stockinette, padding and plaster ≈ 1 cm)
      this.hands = { mould: buildHand(M, x => this.keep(x), 'mould', sc, { bendR: this.R + 0.01 }), point: buildHand(M, x => this.keep(x), 'point', sc * 0.8) };
      Object.values(this.hands).forEach(h => S.scene.add(h.group));
      // the point hand follows the cursor on the skin through the engine's tool posing (CMS check)
      const hp = this.hands.point;
      this.pointTool = { name: 'xc3point', group: hp.group, pose: { lift: 0.004, pressLift: -0.0018, tilt: 1.15, yaw: -0.85, roll: 0, shadow: 0.035 }, press: 0, _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false, tipWorld: () => hp.group.getWorldPosition(new THREE.Vector3()), set() {} };
      this.handState = { s: 0, a: 0.2, ok: false, press: 0 };
      // the forearm comes in from the medic's side, angled off to the lower right (keeps the cast in view)
      this.handTune = { yaw: -0.5, beta: 0.04 };
    }
    makeGuide() {
      const S = this.S;
      const NG = 30, geo = this.keep(gridGeo(GC, NG));
      const mesh = new THREE.Mesh(geo, this.M.guide);
      mesh.frustumCulled = false; mesh.visible = false; mesh.renderOrder = 6;
      S.scene.add(mesh);
      this.guide = { mesh, geo, NG, C: null };
      // CMS blanch spot (a pale disc on the skin)
      const bl = new THREE.Mesh(this.keep(new THREE.CircleGeometry(1, 32)), this.M.blanch);
      bl.visible = false; bl.renderOrder = 5;
      S.scene.add(bl);
      this.blanch = bl;
    }
    // the ghost band where this turn should go (over the visible pass)
    setGuide(C, bw) {
      const g = this.guide, pos = g.geo.attributes.position.array, uv = g.geo.attributes.uv.array, P = new THREE.Vector3();
      for (let j = 0; j <= g.NG; j++) {
        const a = lerp(A0 + 0.15, AFAR - 0.1, j / g.NG);
        for (let i = 0; i <= GC; i++) {
          // enough columns across to follow the curved band profile under it (no dips under the plaster)
          const v = i / GC * 2 - 1, s = this.wCur ? this.zs(this.wCur, C + v * bw / 2) : C + v * bw / 2, k = j * (GC + 1) + i;
          const r = this.under(s, a) + 0.0022;
          this.cyl(s, a, r, P);
          pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
          uv[k * 2] = (j / g.NG) * 3.5; uv[k * 2 + 1] = i / GC;
        }
      }
      g.geo.attributes.position.needsUpdate = true; g.geo.attributes.uv.needsUpdate = true;
      g.geo.computeVertexNormals();
      g.mesh.visible = true; g.C = C;
    }
    hideGuide() { this.guide.mesh.visible = false; this.guide.C = null; }

    // compile every shader up front behind the loading veil (no hitch on the first use)
    prewarm() {
      const S = this.S, shown = [];
      const show = o => { if (o && !o.visible) { o.visible = true; shown.push(o); } };
      Object.values(this.hands).forEach(h => { show(h.group); h.group.position.set(0, -5, 0); });
      show(this.padRoll.group); show(this.guide.mesh); show(this.blanch); show(this.stk.ringMesh); show(this.basin.pickRing); show(this.basin.rip[0].m);
      this.stk.parts.forEach(p => show(p.mesh));
      // one band of each material
      const w = this.makeWrap('pad'), t1 = this.newTurn(w, this.sD - this.L.bw / 2, true);
      const w2 = this.makeWrap('pl'), t2 = this.newTurn(w2, this.sD - this.L.bw / 2, true);
      [t1, t2].forEach(t => { t.phi = 1; this.layRows(t.w, t, 0, 4); t.geo.setDrawRange(0, 4 * AC * 6); show(t.mesh); });
      const dm = this.drips.mesh; dm.count = 1; dm.setMatrixAt(0, new THREE.Matrix4().makeTranslation(0, -5, 0));
      const bm = this.basin.bub; bm.count = 1; bm.setMatrixAt(0, new THREE.Matrix4().makeTranslation(0, -5, 0));
      S.prewarm([], false);
      shown.forEach(o => { o.visible = false; });
      [t1, t2].forEach(t => { S.scene.remove(t.mesh); t.geo.dispose(); });
      dm.count = 0; bm.count = 0;
      this.stk.parts.forEach(p => { p.mesh.visible = false; });
      this.layStock();
    }

    /* ═════════════════════════════ WRAPPING: spiral bands round the limb ═════════════════════════════
       A turn runs φ 0 → 2π from the near side (A0) over the top (visible pass, φ ≤ PASS) and round
       underneath. Its centre s: sA → sB across the pass (a slight slant), then on to the next turn's
       sA underneath (sN). Bands lie on whatever is under them (the thickness fields) and are stamped
       into their field when laid, so every turn sits on the last. */
    makeWrap(kind) {
      const pad = kind === 'pad', L = this.L;
      return {
        kind, pad, bw: L.bw, th: pad ? PAD_TH : PL_TH, field: pad ? this.fPad : this.fPl, mat: pad ? this.M.padding : this.M.plaster,
        zone: pad ? [this.sP - 0.008, this.sD + 0.008] : [this.sP, this.sD], turns: [], uvBase: 0,
      };
    }
    newTurn(w, C, anchor, dir = -1) {
      const geo = this.keep(gridGeo(AC, NSEG));
      const mesh = new THREE.Mesh(geo, w.mat);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false; mesh.visible = false;
      this.S.scene.add(mesh);
      geo.setDrawRange(0, 0);
      const prev = w.turns[w.turns.length - 1] || null;
      const t = { w, C, anchor, dir, adv: anchor ? 0 : 0.5 * w.bw * dir, phi: 0, drawn: 0, mesh, geo, prev, idx: w.turns.length, uv0: w.uvBase };
      w.uvBase += TAU * this.R / 0.05 + 0.37;
      this.setTurnC(t, C, true);
      w.turns.push(t);
      return t;
    }
    // move a turn's centre (and the hidden end of the turn before it, which leads into it)
    setTurnC(t, C, quiet) {
      const q = t.adv * PASS / TAU;
      t.C = C; t.sA = C - q / 2; t.sB = C + q / 2; t.sN = t.sB + t.adv * (TAU - PASS) / TAU;
      // the turn before leads into this one underneath: re-lay its hidden end even for a new turn
      // (it went round to a provisional end; left as it was it pokes past the end of the cast)
      if (t.prev && !t.prev.hiddenStamped) { t.prev.sN = t.sA; if (t.prev.drawn > 0) this.layRows(t.w, t.prev, Math.floor(PASS / (TAU / NSEG)), t.prev.drawn); }
      if (!quiet && t.drawn > 0) this.layRows(t.w, t, 0, t.drawn);
    }
    sc(t, phi) { return phi <= PASS ? lerp(t.sA, t.sB, phi / PASS) : lerp(t.sB, t.sN, (phi - PASS) / (TAU - PASS)); }
    // keep a band inside its zone: what a slanted end turn would lay past it is squashed against the edge
    // (compressed, not clamped: no zero-area quads)
    zs(w, s) { const a = w.zone[0] - 0.002, b = w.zone[1] + 0.002; return s < a ? a - (a - s) * 0.06 : s > b ? b + (s - b) * 0.06 : s; }
    // lay rows k0..k1 of a turn (φ_k = k·2π/NSEG, the last drawn row at the roll)
    layRows(w, t, k0, k1) {
      const pos = t.geo.attributes.position.array, uv = t.geo.attributes.uv.array, P = new THREE.Vector3(), dphi = TAU / NSEG, bw = w.bw;
      k0 = clamp(k0, 0, NSEG); k1 = clamp(k1, 0, NSEG);
      for (let k = k0; k <= k1; k++) {
        const phi = Math.min(k * dphi, t.phi), a = A0 - phi, c = this.sc(t, phi);
        for (let i = 0; i <= AC; i++) {
          const v = i / AC * 2 - 1, s = this.zs(w, c - v * bw / 2), kk = k * (AC + 1) + i;
          const prof = 1 - Math.pow(Math.abs(v), 6);
          const r = this.under(s, a) + w.th * (0.35 + 0.65 * prof) + 0.00015;
          this.cyl(s, a, r, P);
          pos[kk * 3] = P.x; pos[kk * 3 + 1] = P.y; pos[kk * 3 + 2] = P.z;
          uv[kk * 2] = t.uv0 + phi * this.R / 0.05; uv[kk * 2 + 1] = i / AC * (bw / 0.05);
        }
      }
      t.geo.attributes.uv.needsUpdate = true;
      const kmax = Math.max(t.drawn, k1);
      gridNormals(t.geo, AC, NSEG, kk => { const k = Math.floor(kk / (AC + 1)), a = A0 - Math.min(k * dphi, t.phi); return [0, Math.cos(a), Math.sin(a)]; }, Math.max(0, k0 - 1), Math.min(kmax, k1 + 1));
      t.geo.computeBoundingSphere();
    }
    // grow a turn to φ (draws new rows, re-lays the leading one)
    growTurn(t, phi) {
      phi = clamp(phi, 0, TAU);
      if (phi <= t.phi + 1e-6 && t.drawn > 0) return;
      const dphi = TAU / NSEG, from = Math.max(0, t.drawn - 1);
      t.phi = phi;
      const k1 = Math.min(NSEG, Math.ceil(phi / dphi - 1e-6));
      t.drawn = Math.max(t.drawn, k1);
      this.layRows(t.w, t, from, t.drawn);
      t.geo.setDrawRange(0, t.drawn * AC * 6);
      t.mesh.visible = t.drawn > 0;
    }
    // add a piece of a turn (φ0..φ1) to its thickness field (each angle column crossed once per turn)
    stamp(w, t, phi0, phi1) {
      const F = w.field, bw = w.bw;
      for (let j = 0; j < NA; j++) {
        const a = -Math.PI + (j + 0.5) * TAU / NA;
        let phi = A0 - a; phi = ((phi % TAU) + TAU) % TAU;
        if (phi < phi0 || phi >= phi1) continue;
        const c = this.sc(t, phi);
        const i0 = Math.max(0, Math.floor((c - bw / 2 - this.fs0) / DS)), i1 = Math.min(this.NSF - 1, Math.ceil((c + bw / 2 - this.fs0) / DS));
        for (let i = i0; i <= i1; i++) {
          const s = this.fs0 + (i + 0.5) * DS, v = (s - c) / (bw / 2);
          if (Math.abs(v) >= 1 || s < w.zone[0] - 0.002 || s > w.zone[1] + 0.002) continue;
          F[i * NA + j] += w.th * (0.35 + 0.65 * (1 - Math.pow(Math.abs(v), 6)));
        }
      }
    }
    // the pass of a turn is laid: stamp it and the hidden end of the turn before it; count its layers
    commitPass(t) {
      const w = t.w;
      if (t.prev && !t.prev.hiddenStamped) { this.stamp(w, t.prev, PASS, TAU + 1e-6); t.prev.hiddenStamped = true; }
      this.stamp(w, t, 0, PASS);
      t.passStamped = true;
      const arr = w.pad ? this.padLayers : this.layers, z = w.zone;
      for (let i = 0; i < CELLS; i++) {
        const s = lerp(z[0], z[1], (i + 0.5) / CELLS);
        if (Math.abs(s - t.C) <= w.bw / 2 + 1e-4) arr[i] += 1;
      }
    }
    closeWrap(w) {
      const t = w.turns[w.turns.length - 1];
      if (t && !t.hiddenStamped) { t.sN = t.sB; this.growTurn(t, TAU); this.layRows(w, t, 0, NSEG); this.stamp(w, t, PASS, TAU + 1e-6); t.hiddenStamped = true; }
    }
    // the roll sits on the end of the band (screen-height lookup for the drag as in the bleed close-up)
    rollAt(w, t, roll) {
      const phi = t.phi, a = A0 - phi, s = this.sc(t, phi);
      const r = this.under(s, a) + w.th + roll.r;
      const P = this.cyl(s, a, r);
      this.setRoll(roll, P, -phi * (this.R / Math.max(roll.r, 0.008)) - t.idx * 2.1, roll.r);
      roll.group.rotation.x += 0;
      return P;
    }
    angleAtPointer(s, r) {
      const S = this.S, cam = S.camera.position, py = S.pointer.y, P = new THREE.Vector3();
      const lo = AFAR - 0.35, hi = A0 + 0.35, n = 30, vis = [];
      for (let j = 0; j <= n; j++) {
        const a = hi - (j / n) * (hi - lo);
        this.cyl(s, a, r, P);
        if (Math.cos(a) * (cam.y - P.y) + Math.sin(a) * (cam.z - P.z) <= 0) continue;
        vis.push({ a, y: S.project(P).y });
      }
      if (!vis.length) return hi;
      this.span = Math.max(0.05, vis[0].y - vis[vis.length - 1].y);
      if (py >= vis[0].y) return vis[0].a;
      for (let j = 1; j < vis.length; j++) {
        const p0 = vis[j - 1], p1 = vis[j];
        if (py <= p0.y && py >= p1.y) return lerp(p0.a, p1.a, (p0.y - py) / Math.max(1e-6, p0.y - p1.y));
      }
      return lo;
    }

    /* ─────────────── step flow ─────────────── */
    nextStep() {
      this.stepIdx += 1;
      const name = STEPS[this.stepIdx];
      if (!name) return this.finish();
      this.enter(name);
    }
    stepNames() {
      return {
        stockinette: T('c3_s_stock', 'Stockinette'), padding: T('c3_s_pad', 'Cast padding'), dip: T('c3_s_dip', 'Wet the plaster'),
        plaster: T('c3_s_wrap', 'Wrap the plaster'), mould: T('c3_s_mould', 'Mould and set'), fold: T('c3_s_fold', 'Fold the ends'), cms: T('c3_s_cms', 'Check CMS'),
      };
    }
    enter(name) {
      if (this.ph && this.ph.exit) this.ph.exit();
      const make = { stockinette: this.phStock, padding: this.phPad, dip: this.phDip, plaster: this.phPlaster, mould: this.phMould, fold: this.phFold, cms: this.phCms }[name];
      this.ph = make.call(this);
      this.ph.name = name;
      this.ph.t0 = this.t;
      const names = this.stepNames();
      this.pp.set(Object.assign({
        step: this.stepIdx + 1, total: STEPS.length, steps: STEPS.map(s => names[s]), titleTone: '',
        hints: this.hintsFor(this.ph.hints),
      }, this.ph.panelInit()));
      this.updateTools();
      if (this.ph.panel) this.ph.panel();
    }
    hintsFor(own) {
      return (own || []).concat([
        { keys: [T('c3_k_rmb', 'RMB')], label: T('c3_h_look', 'Look around') },
        { keys: [T('c3_k_wheel', 'Wheel')], label: T('c3_h_zoom', 'Zoom') },
        { keys: ['R'], label: T('c3_h_recentre', 'Recentre') },
      ]);
    }
    updateTools() {
      const lbl = {
        stockinette: [T('c3_t_stock', 'Stockinette'), T('c3_t_stock_sub', 'Cotton tube')], padding: [T('c3_t_pad', 'Cast padding'), T('c3_t_pad_sub', 'Undercast roll')],
        dip: [T('c3_t_water', 'Water basin'), T('c3_t_water_sub', 'Lukewarm')], plaster: [T('c3_t_plaster', 'Plaster roll'), T('c3_t_plaster_sub', 'Plaster of Paris')],
        mould: [T('c3_t_hands', 'Palms'), T('c3_t_hands_sub', 'Mould and smooth')], fold: [T('c3_t_fold', 'Fold back'), T('c3_t_fold_sub', 'Stockinette ends')],
        cms: [T('c3_t_cms', 'CMS check'), T('c3_t_cms_sub', 'Circulation · motor · sensation')],
      };
      this.pp.set({
        tools: STEPS.map((s, i) => ({
          key: String(i + 1), label: lbl[s][0], sub: lbl[s][1], icon: STEP_ICON[s],
          // the belt's rendered pictures: a white roll for the padding / plaster rolls, line icons elsewhere
          // (its 'drop' / 'splint' / 'bandage' pictures are a syringe, a SAM splint and a crepe roll)
          img: s === 'padding' || s === 'plaster' ? 'img/tools/gauze-roll.png' : undefined, noImg: s !== 'padding' && s !== 'plaster',
          state: i < this.stepIdx ? 'done' : i === this.stepIdx ? 'active' : 'locked',
          why: T('c3_tool_later', 'Finish the step you are on first.'),
        })),
      });
    }
    pickTool(key) {
      const i = (+key || 0) - 1;
      if (!this.ph || this.finished || i === this.stepIdx || i < 0 || i >= STEPS.length) return;
      if (i < this.stepIdx) this.flash('warn', T('c3_tool_done', 'That step is done.'), 1600);
    }
    stepDone(flash) {
      const ph = this.ph;
      if (!ph || ph.finished) return;
      ph.finished = true;
      // (a restore runs the steps through quietly and moves on itself)
      if (this.quiet) return;
      this.snd('success');
      if (flash) this.flash('ok', flash, 1800);
      this.cursor(null, '');
      const name = ph.name;
      setTimeout(() => { if (this.alive && this.ph === ph && ph.name === name) this.nextStep(); }, 900);
    }
    stageCursor(cls) { const c = `xc3-stage ${cls || ''}`.trim(); if (this.stage.className !== c) this.stage.className = c; }
    cursor(p, text, tone) { this.cur.p = p; this.cur.text = text || ''; this.cur.tone = tone || ''; }
    flashOnce(type, text, ms) { if (this.quiet) return; const n = performance.now(); if (this.lastFlash === text && n - this.lastFlashAt < 1800) return; this.lastFlash = text; this.lastFlashAt = n; this.flash(type, text, ms || 2000); }
    // sounds and notes go through these: a restore replays the game quietly
    flash(type, text, ms) { if (!this.quiet && this.pp) this.pp.flash(type, text, ms); }
    snd(...a) { if (!this.quiet) this.ctx.sound(...a); }
    click(f) { if (!this.quiet) NZA.audio.click(f); }

    /* ─────────────── input ─────────────── */
    down(e) {
      if (!this.ready || e.button !== 0 || this.finished) return;
      this.lmb = true;
      if (this.ph && this.ph.down) this.ph.down(e);
    }
    up(e) {
      if (e.button !== 0) return;
      const was = this.lmb;
      this.lmb = false;
      if (was && this.ph && this.ph.up) this.ph.up(e);
    }
    key(e) {
      if (/^Digit[1-9]$/.test(e.code || '') || e.key === 'Enter') return this.pp.key(e);
      if (this.ph && this.ph.key) return this.ph.key(e);
      return false;
    }
    abort() { this.ctx.post('abort'); }

    /* ─────────────── per frame ─────────────── */
    frame(dt, render) {
      if (!this.alive || !this.S) return;
      this.t += dt;
      if (this.ph && this.ph.tick) this.ph.tick(dt);
      this.fluidTick(dt);
      if (this.wet > 0 && this.plRoll.group.visible && this.dripOn) {
        this.dripT = (this.dripT || 0) - dt;
        if (this.dripT <= 0) { this.dripT = lerp(1.6, 0.12, this.wet); this.drip(this.plRoll.group.position.clone().add(new THREE.Vector3(0, -this.plRoll.r, 0))); }
        this.wet = Math.max(0, this.wet - dt * 0.05);
      }
      if (!render) return;
      if (this.guide.mesh.visible) this.guide.mesh.material.opacity = 0.55 + Math.sin(this.t * 4) * 0.25;
      this.drawCursor();
      const n = performance.now();
      if (n - this.uiAt > 120) { this.uiAt = n; if (this.ph && this.ph.panel) this.ph.panel(); }
    }
    drawCursor() {
      const c = this.cur, S = this.S;
      const on = !this.finished && (c.p !== null || !!c.text);
      this.curEl.classList.toggle('on', on);
      if (!on) return;
      if (!this.zoom) this.zoom = parseFloat(getComputedStyle(this.app.el).zoom) || 1;
      const x = S.pointer.x * window.innerWidth / this.zoom, y = S.pointer.y * window.innerHeight / this.zoom;
      this.curEl.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`;
      const cls = `xc3-cur on ${c.p === null ? 'noring' : ''} ${c.tone}`;
      if (this.curEl.className !== cls) this.curEl.className = cls;
      if (c.p !== null) this.curFg.setAttribute('stroke-dasharray', `${(clamp(c.p, 0, 1) * 119.4).toFixed(1)} 120`);
      if (this.curTx.textContent !== c.text) this.curTx.textContent = c.text;
    }

    /* ═════════════════════════════ 1. STOCKINETTE ═════════════════════════════ */
    phStock() {
      const g = this, st = this.stk;
      this.frameStep('stockinette', !this.stepIdx);
      st.parts.forEach(p => { p.mesh.visible = true; });
      this.layStock();
      this.stockOn = true;
      const total = st.s0 - st.sE;
      const ph = {
        grab: false, gS: 0, gR: 0,
        hints: [{ keys: [T('c3_k_drag', 'Drag')], label: T('c3_h_stock', 'roll it along the limb') }],
        panelInit() {
          return { title: T('c3_p_stock', 'Roll on the stockinette'), text: T('c3_p_stock_t', '**Drag the rolled stockinette** along the limb to the far end of the cast area. It unrolls smoothly behind the roll, with no creases.') };
        },
        // where the cursor is along the limb (on the line over the top of the roll)
        curS() { return g.sAtPointer(0.25, g.R + 0.006); },
        down() { this.grab = true; this.gS = this.curS(); this.gR = st.target; g.click(520); },
        pointer() { if (this.grab && g.lmb) st.target = clamp(Math.min(st.target, this.gR + (this.curS() - this.gS)), st.sE, st.s0); },
        up() { this.pointer(); this.grab = false; },
        tick(dt) {
          if (this.grab && g.lmb) this.pointer();
          if (st.ring > st.target + 1e-5) {
            st.ring = Math.max(st.target, st.ring - 0.45 * dt);
            g.layStock();
            if (Math.random() < dt * 6) g.snd('noise', 60, { vol: 0.025, lp: 2600, hp: 900 });
          }
          const prog = clamp((st.s0 - st.ring) / total, 0, 1);
          if (st.ring <= st.sE + 0.0015 && !this.finished) {
            st.ring = st.sE; st.done = true; g.layStock();
            g.stepDone(T('c3_ok_stock', 'Stockinette on, smooth and straight.'));
            return;
          }
          if (this.finished) return;
          const ringP = new THREE.Vector3(st.ring, 0.004, 0);
          const near = g.pxTo(ringP) < Math.max(90, window.innerHeight * 0.1);
          g.stageCursor(this.grab && g.lmb ? 'grabbing' : 'grab');
          if (this.grab && g.lmb) g.cursor(prog, T('c3_cur_rolling', 'Rolling on…'), 'teal');
          else g.cursor(prog > 0.01 ? prog : null, near || prog > 0.01 ? T('c3_cur_stock', 'Drag it left along the limb') : '', '');
        },
        panel() {
          const prog = clamp((st.s0 - st.ring) / total, 0, 1);
          g.pp.set({
            stats: [{ id: 'len', label: T('c3_st_on', 'Rolled on'), value: String(Math.round(prog * total * 100)), unit: 'cm' }],
            wide: { label: T('c3_w_stock', 'Stockinette'), value: String(Math.round(prog * 100)), unit: '%', meter: { value: prog }, caption: T('c3_cap_stock', 'Past both ends of the cast'), captionTone: 'teal' },
          });
        },
        exit() { st.done = true; st.ring = st.sE; g.layStock(); },
      };
      return ph;
    }

    /* ═════════════════════════════ 2 / 4. WRAP (padding, plaster) ═════════════════════════════ */
    phWrapGeneric(kind) {
      const g = this, S = this.S, isPad = kind === 'pad';
      const w = this.wCur = isPad ? (this.wPad = this.makeWrap('pad')) : (this.wPl = this.makeWrap('pl'));
      const roll = isPad ? this.padRoll : this.plRoll;
      const bw = w.bw, maxPass = isPad ? 1 : 3;
      if (!isPad) { roll.inner.children[0].material = this.M.plaster; }
      this.frameStep(isPad ? 'padding' : 'plaster');
      this.useHand(null);
      const ph = {
        w, roll, pass: -1, dir: -1, phase: 'idle', turn: null, target: 0, grab: false, evt: [], anchorsLeft: 0, endC: 0, startC: 0,
        ov: 0.5, ovShow: false, turnsUser: 0, nudge: 0, drift: 0, drift0: 0,
        hints: [{ keys: [T('c3_k_drag', 'Drag')], label: T('c3_h_wrap', 'roll it up over the limb') }, { keys: [T('c3_k_side', '← →')], label: T('c3_h_steer', 'steer the overlap') }],
        panelInit() {
          return isPad
            ? { title: T('c3_p_pad', 'Wrap the cast padding'), text: T('c3_p_pad_t', '**Drag the roll up** over the limb: it goes round underneath by itself. Keep each turn **half over the last one**: follow the teal guide, steer sideways if it drifts.') }
            : { title: T('c3_p_wrap', 'Wrap the plaster'), text: T('c3_p_wrap_t', '**Drag the roll up** over the limb, each turn **half over the last** (teal guide). Roll it on, do not pull. Up the limb and back: every part needs %s–%s layers.', g.minL, g.maxL) };
        },
        startPass() {
          this.pass += 1;
          this.dir = this.pass % 2 === 0 ? -1 : 1;
          const z = w.zone;
          this.startC = this.dir < 0 ? z[1] - bw / 2 : z[0] + bw / 2;
          this.endC = this.dir < 0 ? z[0] + bw / 2 : z[1] - bw / 2;
          this.anchorsLeft = isPad ? 1 : this.pass < 2 ? 2 : 1;
          this.nextTurn();
        },
        nextTurn() {
          if (this.anchorsLeft > 0) {
            this.anchorsLeft -= 1;
            this.turn = g.newTurn(w, this.startC, true, this.dir);
            this.phase = 'anchor'; this.animT = 0;
            g.hideGuide();
            return;
          }
          const last = w.turns[w.turns.length - 1];
          const ideal = this.clampC(last.C + this.dir * bw * 0.5, last.C);
          this.turn = g.newTurn(w, ideal, false, this.dir);
          this.ideal = ideal;
          this.phase = 'wait'; this.target = 0; this.grab = false; this.nudge = 0; this.drift = 0; this.drift0 = 0;
          // a press made while the last turn was still going round counts for this one
          if (this.pending && g.lmb) { this.grab = true; this.gS = null; this.drift0 = 0; }
          this.pending = false;
          g.setGuide(ideal, bw);
          g.growTurn(this.turn, 0.0001);
          g.rollAt(w, this.turn, roll);
        },
        clampC(C, prevC) {
          const lo = prevC + this.dir * bw * 0.15, hi = prevC + this.dir * bw * 1.0;
          C = this.dir < 0 ? clamp(C, hi, lo) : clamp(C, lo, hi);
          return this.dir < 0 ? Math.max(C, this.endC) : Math.min(C, this.endC);
        },
        aim() { return clamp(A0 - g.angleAtPointer(g.sc(this.turn, this.turn.phi), g.under(this.turn.C, 0.3) + w.th), 0, PASS); },
        // steering: the turn's centre follows the cursor sideways from where the drag began (a new drag
        // carries on from where the last one left it), plus the ← → / A D nudges
        steer() {
          const t = this.turn, a = A0 - t.phi;
          if (this.grab && g.lmb) {
            const cs = g.sAtPointer(a, g.under(t.C, a) + w.th);
            if (this.gS === null) this.gS = cs;
            this.drift = this.drift0 + (cs - this.gS);
          }
          this.applyC();
        },
        applyC() {
          const t = this.turn;
          const C = this.clampC(this.ideal + this.nudge + this.drift, t.prev.C);
          if (Math.abs(C - t.C) > 1e-5) g.setTurnC(t, C);
          this.ov = clamp(1 - this.dir * (C - t.prev.C) / bw, 0, 1);
          this.ovShow = true;
        },
        key(e) {
          const k = e.key, d = k === 'ArrowLeft' || k === 'a' || k === 'A' ? -1 : k === 'ArrowRight' || k === 'd' || k === 'D' ? 1 : 0;
          if (!d) return false;
          if ((this.phase === 'wait' || this.phase === 'drag') && this.turn && this.turn.prev) { this.nudge = clamp(this.nudge + d * 0.004, -bw, bw); this.applyC(); }
          return true;
        },
        pointer() {
          if (this.phase !== 'wait' && this.phase !== 'drag') return;
          if (!this.grab || !g.lmb) return;
          const tg = this.aim();
          if (tg > this.target) this.target = tg;
          if (this.phase === 'wait' && this.target > 0.02) this.phase = 'drag';
          this.steer();
        },
        down() {
          if (this.phase !== 'wait' && this.phase !== 'drag') { this.pending = this.phase === 'round' || this.phase === 'anchor'; return; }
          this.grab = true; this.gS = null; this.drift0 = this.drift;
          this.steer();
          this.target = Math.max(this.target, this.aim());
        },
        up() { if (this.grab) this.pointer(); this.grab = false; this.pending = false; },
        tick(dt) {
          if (this.phase === 'idle') { this.startPass(); return; }
          const t = this.turn;
          if (this.phase === 'anchor') {
            // an anchor turn goes straight round by itself
            this.animT += dt;
            const f = clamp(this.animT / 0.7, 0, 1), phi = f * TAU;
            g.growTurn(t, phi);
            if (!t.passStamped && phi >= PASS) g.commitPass(t);
            g.rollAt(w, t, roll);
            g.cursor(null, '', '');
            if (f >= 1) this.afterTurn();
            return;
          }
          if (this.phase === 'round') {
            this.animT += dt;
            const f = clamp(this.animT / 0.45, 0, 1), e = f * f * (3 - 2 * f);
            g.growTurn(t, lerp(PASS, TAU, e));
            g.rollAt(w, t, roll);
            g.cursor(null, '', '');
            if (f >= 1) this.afterTurn();
            return;
          }
          if (this.phase === 'done') return;
          // wait / drag: the roll catches up with the cursor
          const held = this.grab && g.lmb;
          if (held) this.pointer();
          const phi = Math.min(PASS, t.phi + Math.max(0, Math.min(this.target - t.phi, CATCH * dt)));
          if (phi > t.phi + 1e-5) { g.growTurn(t, phi); if (Math.random() < dt * 8) g.snd('noise', 70, { vol: 0.03, lp: isPad ? 2400 : 1600, hp: 500 }); }
          g.rollAt(w, t, roll);
          // (the guide only moves with the ideal: nothing under it changes until the pass is stamped)
          if (g.guide.C !== this.ideal) g.setGuide(this.ideal, bw);
          if (t.phi >= PASS - 1e-4) { this.endPass(); return; }
          g.stageCursor(held ? 'grabbing' : 'grab');
          const ov = this.ov, good = Math.abs(ov - 0.5) <= 0.12;
          if (held && this.ovShow) g.cursor(t.phi / PASS, ov < 0.38 ? T('c3_cur_gap', 'Overlap %s%: too little', Math.round(ov * 100)) : ov > 0.62 ? T('c3_cur_thick', 'Overlap %s%: too much', Math.round(ov * 100)) : T('c3_cur_half', 'Overlap %s%', Math.round(ov * 100)), good ? 'teal' : 'amber');
          else g.cursor(null, held ? '' : T('c3_cur_drag', 'Drag up over the limb'), '');
        },
        endPass() {
          const t = this.turn;
          g.growTurn(t, PASS);
          g.commitPass(t);
          g.hideGuide();
          const ov = clamp(1 - this.dir * (t.C - t.prev.C) / bw, 0, 1);
          const q = clamp(1 - Math.abs(ov - 0.5) / 0.38, 0, 1);
          (isPad ? g.res.padQ : g.res.plQ).push(q);
          this.turnsUser += 1;
          g.click(q > 0.7 ? 720 : 480);
          if (ov < 0.3) g.flashOnce('warn', T('c3_ov_gap', 'That turn barely overlaps: thin spot. Keep half over the last turn.'), 1800);
          else if (ov > 0.72) g.flashOnce('warn', T('c3_ov_thick', 'Too much overlap: it builds up thick there.'), 1800);
          this.grab = false; this.ovShow = false;
          // lead the underside to where the next turn will start (at the end of a pass: straight round)
          if (Math.abs(t.C - this.endC) < 1e-4) t.sN = t.sB;
          else { const nC = this.clampC(t.C + this.dir * bw * 0.5, t.C); t.sN = nC - (0.5 * bw * this.dir * PASS / TAU) / 2; }
          this.phase = 'round'; this.animT = 0;
        },
        // after a full turn: on along the limb, the next pass, or done
        afterTurn() {
          const t = this.turn;
          const atEnd = Math.abs(t.C - this.endC) < 1e-4 && !t.anchor;
          if (this.anchorsLeft > 0 || (!atEnd && !(t.anchor && Math.abs(this.startC - this.endC) < 1e-4))) { this.nextTurn(); return; }
          if (!atEnd) { this.nextTurn(); return; }
          // the pass reached the end
          if (isPad || this.pass + 1 >= maxPass || (this.pass >= 1 && g.layerMin() >= g.minL)) { this.finishWrap(); return; }
          g.flashOnce('ok', T('c3_pass_back', 'Good: now back down the limb.'), 1600);
          this.startPass();
        },
        finishWrap() {
          this.phase = 'done';
          g.closeWrap(w);
          roll.group.visible = false;
          g.hideGuide();
          const qs = isPad ? g.res.padQ : g.res.plQ, q = qs.length ? qs.reduce((a, b) => a + b, 0) / qs.length : 0.6;
          if (isPad) g.stepDone(q > 0.7 ? T('c3_ok_pad', 'Padding on: even, half over each turn.') : T('c3_ok_pad_uneven', 'Padding on, a little uneven.'));
          else {
            const mn = g.layerMin(), mx = g.layerMax();
            g.stepDone(mx > g.maxL ? T('c3_ok_wrap_thick', 'Plaster on, too thick in places (%s layers).', mx) : mn < g.minL ? T('c3_ok_wrap_thin', 'Plaster on, thin in places (%s layers).', mn) : T('c3_ok_wrap', 'Plaster on: %s–%s layers everywhere.', mn, mx));
          }
        },
        exit() { if (this.phase !== 'done') { g.closeWrap(w); roll.group.visible = false; g.hideGuide(); } },
        panel() {
          const t = this.turn, active = (this.phase === 'drag' || this.phase === 'wait') && this.ovShow;
          const ov = this.ov, tone = active && Math.abs(ov - 0.5) > 0.12 ? 'amber' : '';
          const wide = { label: T('c3_w_overlap', 'Overlap'), value: active ? String(Math.round(ov * 100)) : '--', unit: active ? '%' : '', tone, meter: { value: active ? ov : 0, zone: [0.38, 0.62], mark: active ? ov : null, noFill: !active }, caption: T('c3_cap_overlap', 'Half over the last turn'), captionTone: 'teal' };
          let stats;
          if (isPad) {
            const cov = g.padLayers.filter(x => x >= 1).length / CELLS;
            stats = [{ id: 'turns', label: T('c3_st_turns', 'Turns'), value: String(w.turns.length) }, { id: 'cov', label: T('padding', 'Padding'), value: String(Math.round(cov * 100)), unit: '%', meter: { value: cov, zone: [0.95, 1] } }];
          } else {
            const mn = g.layerMin(), mx = g.layerMax();
            stats = [
              { id: 'pass', label: T('c3_st_pass', 'Pass'), value: `${Math.max(1, this.pass + 1)}` },
              { id: 'mn', label: T('thinnest', 'Thinnest'), value: mn.toFixed(0), tone: mn >= g.minL ? 'teal' : 'amber' },
              { id: 'mx', label: T('thickest', 'Thickest'), value: mx.toFixed(0), tone: mx > g.maxL ? 'red' : '' },
            ];
          }
          void t;
          g.pp.set({ stats, wide });
        },
      };
      return ph;
    }
    layerMin() { let m = Infinity; for (let i = 0; i < CELLS; i++) m = Math.min(m, this.layers[i]); return m === Infinity ? 0 : m; }
    layerMax() { let m = 0; for (let i = 0; i < CELLS; i++) m = Math.max(m, this.layers[i]); return m; }
    phPad() { return this.phWrapGeneric('pad'); }
    phPlaster() {
      const ph = this.phWrapGeneric('pl');
      this.wet = Math.max(this.wet || 0, 0.6); this.dripOn = true;
      return ph;
    }

    /* ═════════════════════════════ 3. DIP THE PLASTER ROLL ═════════════════════════════ */
    phDip() {
      const g = this, b = this.basin, roll = this.plRoll;
      this.frameStep('dip');
      this.useHand(null);
      roll.inner.children[0].material = this.M.plasterDry;
      this.setRoll(roll, b.home, 0.3, roll.r);
      const pos = b.home.clone(), goal = b.home.clone();
      const carryY = b.floor + b.H + 0.045;
      const ph = {
        held: false, soak: 0, inWater: false, lifting: 0, spin: 0.3, pos, goal,
        hints: [{ keys: [T('c3_k_lmb', 'Hold LMB')], label: T('c3_h_dip', 'carry it, hold it under') }],
        panelInit() { return { title: T('c3_p_dip', 'Wet the plaster roll'), text: T('c3_p_dip_t', '**Pick up the plaster roll** (click and hold it), carry it into the water and **keep it under** until the bubbles stop. Then let go.') }; },
        overWater(P) { return P && Math.hypot(P.x - b.x, P.z - b.z) < b.wr - roll.r * 0.6; },
        // (carrying on) the roll lies under the water in the middle of the basin, where it was let go
        sink() {
          const W = new THREE.Vector3(b.x, Math.max(b.floor + 0.007 + roll.r, b.waterY - roll.r * 1.08), b.z);
          pos.copy(W); goal.copy(W);
          this.inWater = true;
          g.setRoll(roll, pos, this.spin, roll.r);
        },
        // is the cursor on the roll (its whole length, plus a margin)? screen distance to its axis vs its screen radius
        onRoll() {
          const S = g.S, W = window.innerWidth, Hh = window.innerHeight, v = new THREE.Vector3();
          const A = S.project(v.copy(pos).setX(pos.x - roll.w / 2)), e = S.project(v.copy(pos).setX(pos.x + roll.w / 2));
          const top = S.project(v.copy(pos).setY(pos.y + roll.r)), mid = S.project(pos);
          const px = S.pointer.x * W, py = S.pointer.y * Hh, ax = A.x * W, ay = A.y * Hh, dx = (e.x - A.x) * W, dy = (e.y - A.y) * Hh;
          const k = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy || 1), 0, 1);
          const d = Math.hypot(px - ax - dx * k, py - ay - dy * k), rpx = Math.hypot((top.x - mid.x) * W, (top.y - mid.y) * Hh);
          return d < rpx + Math.max(28, Hh * 0.03);
        },
        down() {
          if (this.lifting) return;
          const near = this.onRoll() || (this.inWater && g.pxTo(new THREE.Vector3(b.x, b.waterY, b.z)) < Math.max(140, window.innerHeight * 0.16));
          if (!near) { g.flashOnce('warn', T('c3_dip_pick', 'Click and hold the plaster roll to pick it up.'), 1600); return; }
          this.held = true; g.click(500);
        },
        up() {
          if (!this.held) return;
          this.held = false;
          if (this.soak >= 1) this.lift();
          else if (!this.inWater) { goal.copy(b.home); }
        },
        pointer() { if (this.held && g.lmb) this.follow(); },
        follow() {
          // over the water it goes right under, below the cursor (picked on the water plane, no parallax)
          const W = g.pickPlane(b.waterY);
          if (this.overWater(W)) {
            W.y = Math.max(b.floor + 0.007 + roll.r, b.waterY - roll.r * 1.08);
            // the whole roll stays inside the bowl (narrower near the bottom)
            const Rb = b.botR - 0.004, hx = roll.w / 2, mx = Math.max(0, Rb - hx);
            const dx = clamp(W.x - b.x, -mx, mx), mz = Math.sqrt(Math.max(0, Rb * Rb - Math.pow(hx + Math.abs(dx), 2)));
            W.x = b.x + dx; W.z = b.z + clamp(W.z - b.z, -mz, mz);
            goal.copy(W); return;
          }
          const P = g.pickPlane(carryY);
          if (!P) return;
          // keep it over the drape near the basin
          P.x = clamp(P.x, b.x - b.rimR - 0.16, b.x + b.rimR); P.z = clamp(P.z, b.z - b.rimR - 0.04, b.z + b.rimR + 0.03);
          goal.set(P.x, carryY, P.z);
        },
        lift() {
          this.lifting = 0.001;
          g.snd('noise', 220, { vol: 0.05, lp: 1800, hp: 300 });
          g.wet = 1; g.dripOn = true;
          b.milk = Math.min(1, b.milk + 0.5);
        },
        tick(dt) {
          if (this.held && g.lmb) this.follow();
          if (this.lifting) {
            this.lifting += dt;
            const f = clamp(this.lifting / 0.9, 0, 1);
            goal.set(b.x, b.waterY + 0.07 + f * 0.02, b.z);
            pos.lerp(goal, 1 - Math.exp(-dt * 8));
            g.setRoll(roll, pos, this.spin, roll.r * (1 - 0.06 * Math.sin(f * Math.PI)));
            if (Math.random() < dt * 12) g.drip(pos.clone().add(new THREE.Vector3(0, -roll.r, 0)));
            if (f >= 1 && !this.finished) { roll.inner.children[0].material = g.M.plaster; g.stepDone(T('c3_ok_dip', 'Soaked through. Squeeze gently and start wrapping.')); }
            g.cursor(null, '', '');
            return;
          }
          pos.lerp(goal, 1 - Math.exp(-dt * 12));
          this.inWater = pos.y < b.waterY + roll.r * 0.3 && this.overWater(pos);
          if (this.inWater) {
            const prev = this.soak;
            this.soak = Math.min(1, this.soak + dt / 3.2);
            b.stir = Math.min(1, (b.stir || 0) + dt * 2);
            // bubbles stream off the roll while air is still in it
            const rate = (1 - this.soak) * 70;
            for (let k = 0; k < 4 && Math.random() < rate * dt / 4; k++) b.bubbles.push({ p: pos.clone().add(new THREE.Vector3((Math.random() - 0.5) * roll.w * 0.8, roll.r * (Math.random() - 0.3), (Math.random() - 0.5) * roll.r)), v: 0.08 + Math.random() * 0.08, r: 0.0009 + Math.random() * 0.0022, ph: Math.random() * 9 });
            if (b.bubbles.length > 48) b.bubbles.splice(0, b.bubbles.length - 48);
            if (prev < 1 && this.soak >= 1) { g.click(820); g.flashOnce('ok', T('c3_dip_full', 'The bubbles stopped: let go to lift it out.'), 1800); }
            if (prev === 0) g.ripple(pos, 0.05);
            if (!this.held && this.soak >= 1) this.lift();
          }
          g.setRoll(roll, pos, this.spin, roll.r);
          // the obvious next thing: the roll while it waits, the water while it is carried
          const atHome = !this.held && !this.inWater && pos.distanceTo(b.home) < 0.01;
          b.pickRing.visible = atHome; b.dropRing.visible = this.held && !this.inWater;
          b.ringMat.opacity = 0.45 + 0.3 * Math.sin(g.t * 5);
          const over = !this.held && this.onRoll();
          g.stageCursor(this.held ? 'grabbing' : over ? 'grab' : '');
          if (this.held && this.inWater) g.cursor(this.soak, this.soak >= 1 ? T('c3_cur_letgo', 'Let go') : T('c3_cur_soak', 'Soaking… bubbles'), 'teal');
          else if (this.held) g.cursor(this.soak > 0 ? this.soak : null, T('c3_cur_water', 'Into the water'), '');
          else g.cursor(null, over ? T('c3_cur_pick', 'Hold LMB: pick it up') : '', '');
        },
        exit() {
          b.bubbles.length = 0;
          b.pickRing.visible = false; b.dropRing.visible = false;
        },
        panel() {
          g.pp.set({
            stats: [{ id: 'water', label: T('c3_st_water', 'Water'), value: '24', unit: '°C' }, { id: 'soak', label: T('c3_st_soak', 'Soaked'), value: String(Math.round(this.soak * 100)), unit: '%' }],
            wide: { label: T('c3_w_soak', 'Soak'), value: String(Math.round(this.soak * 100)), unit: '%', meter: { value: this.soak }, caption: this.inWater ? T('c3_cap_bubbles', 'Until the bubbles stop') : T('c3_cap_dip', 'Hold it under the water'), captionTone: 'teal' },
          });
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 5. MOULD AND SET ═════════════════════════════
       The plaster turns become one shell; rubbing (cursor distance with LMB held) smooths the section
       under the palm. Mould = the mean of the 24 sections (green band 62–86 %, as the 2D game). */
    buildShell() {
      if (this.shell) return this.shell;
      const S = this.S, L = this.L;
      const s0 = this.sP - 0.0005, s1 = this.sD + 0.0005, NSs = Math.ceil((s1 - s0) / 0.002), NAs = 96;
      // a smoothed copy of the plaster field (a blur along and round) for the moulded surface
      const F = this.fPl, Fs = new Float32Array(F.length), tmp = new Float32Array(F.length), NSF = this.NSF;
      const rad = Math.round(0.009 / DS), ra = 3;
      for (let j = 0; j < NA; j++) for (let i = 0; i < NSF; i++) { let acc = 0, n = 0; for (let d = -rad; d <= rad; d++) { const ii = i + d; if (ii < 0 || ii >= NSF) continue; acc += F[ii * NA + j]; n++; } tmp[i * NA + j] = acc / n; }
      for (let i = 0; i < NSF; i++) for (let j = 0; j < NA; j++) { let acc = 0; for (let d = -ra; d <= ra; d++) acc += tmp[i * NA + ((j + d + NA) % NA)]; Fs[i * NA + j] = acc / (ra * 2 + 1); }
      // the ends stay where the raw plaster ends (no blur past the edge)
      for (let i = 0; i < NSF; i++) for (let j = 0; j < NA; j++) { const k = i * NA + j; if (F[k] <= 1e-6) Fs[k] = 0; else Fs[k] = Math.max(Fs[k], F[k] * 0.25); }
      this.fPlS = Fs;
      const geo = this.keep(gridGeo(NAs, NSs, true));
      const uv = geo.attributes.uv.array;
      for (let j = 0; j <= NSs; j++) for (let i = 0; i <= NAs; i++) { const k = j * (NAs + 1) + i; uv[k * 2] = (i / NAs) * TAU * this.R / 0.05; uv[k * 2 + 1] = (lerp(s0, s1, j / NSs) - s0) / 0.05; }
      geo.attributes.uv.needsUpdate = true;
      const mesh = new THREE.Mesh(geo, this.M.plaster);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false;
      S.scene.add(mesh);
      this.shell = { mesh, geo, s0, s1, NSs, NAs, dents: [] };
      // the plaster displayed: raw → smoothed by the mould amount of its section (dents past 1)
      this.plDisp = (s, a) => {
        const raw = this.fAt(this.fPl, s, a);
        if (raw <= 0) return 0;
        const m = this.mouldAt(s);
        const sm = this.fAt(this.fPlS, s, a);
        let v = lerp(raw, sm, clamp(m, 0, 1));
        if (m > 1) v -= (m - 1) * 0.004 * (0.6 + 0.4 * Math.cos(a - 0.3));
        return Math.max(0.0003, v);
      };
      this.wPl && this.wPl.turns.forEach(t => { t.mesh.visible = false; });
      this.layShell();
      void L;
      return this.shell;
    }
    mouldAt(s) {
      const f = (s - this.sP) / (this.sD - this.sP) * CELLS - 0.5, i = Math.floor(f), t = f - i;
      const a = this.mouldM[clamp(i, 0, CELLS - 1)], b = this.mouldM[clamp(i + 1, 0, CELLS - 1)];
      return lerp(a, b, clamp(t, 0, 1));
    }
    // re-lay the shell (all of it, or only the rows between s sa..sb: where the palm has just been)
    layShell(sa, sb) {
      const sh = this.shell, pos = sh.geo.attributes.position.array, P = new THREE.Vector3();
      const part = sa !== undefined, J = s => Math.round((s - sh.s0) / (sh.s1 - sh.s0) * sh.NSs);
      const j0 = part ? clamp(J(sa) - 1, 0, sh.NSs) : 0, j1 = part ? clamp(J(sb) + 1, 0, sh.NSs) : sh.NSs;
      if (j1 < j0) return;
      for (let j = j0; j <= j1; j++) {
        const s = lerp(sh.s0, sh.s1, j / sh.NSs);
        for (let i = 0; i <= sh.NAs; i++) {
          const a = (i / sh.NAs) * TAU - Math.PI, k = j * (sh.NAs + 1) + i;
          const r = this.under(s, a) + 0.0001;
          this.cyl(s, a, r, P);
          pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
        }
      }
      gridNormals(sh.geo, sh.NAs, sh.NSs, k => { const a = ((k % (sh.NAs + 1)) / sh.NAs) * TAU - Math.PI; return [0, Math.cos(a), Math.sin(a)]; }, Math.max(0, j0 - 1), Math.min(sh.NSs, j1 + 1));
      if (!part) sh.geo.computeBoundingSphere();
    }
    // the mould hand rests on the cast at (s, a): palm on the top, fingers curled over it
    placeMouldHand(s, a, press) {
      const h = this.hands.mould, R = this.R;
      const r = this.under(s, a) + 0.0035 - 0.0025 * press;
      const P = this.cyl(s, a, r);
      const n = new THREE.Vector3(0, Math.cos(a), Math.sin(a)), ta = new THREE.Vector3(0, -Math.sin(a), Math.cos(a));
      // the forearm comes in from the medic's side (toward the viewer, a little to the right)
      const yaw = this.handTune.yaw, beta = this.handTune.beta;
      const Y = ta.clone().multiplyScalar(Math.cos(yaw)).add(new THREE.Vector3(1, 0, 0).multiplyScalar(Math.sin(-yaw))).normalize();
      Y.multiplyScalar(Math.cos(beta)).addScaledVector(n, Math.sin(beta)).normalize();
      const Z = n.clone().addScaledVector(Y, -n.dot(Y)).normalize();
      const X = new THREE.Vector3().crossVectors(Y, Z).normalize();
      const m = new THREE.Matrix4().makeBasis(X, Y, Z);
      h.group.quaternion.setFromRotationMatrix(m);
      h.group.position.copy(P);
      h.group.visible = true;
      void R;
    }
    useHand(name) {
      const S = this.S;
      this.hands.mould.group.visible = false;
      if (name === 'point') S.tools.use(this.pointTool);
      else { S.tools.use(null); this.hands.point.group.visible = false; }
      this.handName = name;
    }
    phMould() {
      const g = this, S = this.S;
      this.frameStep('mould');
      this.buildShell();
      this.dripOn = false;
      const hs = this.handState;
      hs.ok = false;
      const ph = {
        phase: 'mould', work: WORK_TIME, setting: 0, last: null, overWarned: false, idleT: 0,
        hints: [{ keys: [T('c3_k_lmb', 'Hold LMB')], label: T('c3_h_rub', 'rub with the palm') }],
        panelInit() { return { title: T('c3_p_mould', 'Mould the cast'), text: T('c3_p_mould_t', '**Hold {LMB} and rub** the whole cast with your palm, end to end, to smooth it before it sets. Stop in the green band: rubbing one spot too long dents it.') }; },
        contact() {
          const hit = g.pickCyl(g.R + 0.012);
          if (!hit) return null;
          return { s: clamp(hit.s, g.sP - 0.01, g.sD + 0.01), a: clamp(hit.a, -0.45, 0.95) };
        },
        // rub along the segment from the last contact: every section the palm passes gets smoother
        rub(c) {
          if (!this.last) { this.last = c; return; }
          const ds = c.s - this.last.s, da = (c.a - this.last.a) * g.R, dist = Math.hypot(ds, da);
          if (dist < 1e-5) return;
          // the palm's footprint: flat under the palm (≈ 4.4 cm across), fading out over 2 cm on each side
          const steps = Math.max(1, Math.ceil(dist / 0.004)), FULL = 0.022, EDGE = 0.04;
          for (let k = 1; k <= steps; k++) {
            const s = lerp(this.last.s, c.s, k / steps), seg = dist / steps;
            for (let i = 0; i < CELLS; i++) {
              const cs = lerp(g.sP, g.sD, (i + 0.5) / CELLS), d = Math.abs(cs - s);
              if (d >= EDGE) continue;
              g.mouldM[i] = Math.min(1.25, g.mouldM[i] + seg / 0.45 * (d <= FULL ? 1 : 1 - (d - FULL) / (EDGE - FULL)));
            }
          }
          // what changed: the palm's footprint along the stroke, plus a section (the mould is read between section centres)
          const pad = EDGE + (g.sD - g.sP) / CELLS;
          const lo = Math.min(this.last.s, c.s) - pad, hi = Math.max(this.last.s, c.s) + pad;
          this.dLo = this.dirty ? Math.min(this.dLo, lo) : lo; this.dHi = this.dirty ? Math.max(this.dHi, hi) : hi;
          this.last = c;
          this.dirty = true;
        },
        down() {
          if (this.phase === 'setting') {
            const hit = g.pickCyl(g.R + 0.012);
            if (hit && hit.s > g.sP - 0.005 && hit.s < g.sD + 0.005) this.crack(hit);
            return;
          }
          const c = this.contact();
          this.last = c;
          if (!c) g.flashOnce('warn', T('c3_mould_on', 'Put your palm on the cast.'), 1500);
        },
        up() { this.last = null; },
        pointer() { if (this.phase === 'mould' && g.lmb) { const c = this.contact(); if (c) { this.rub(c); hs.s = c.s; hs.a = c.a; } else this.last = null; } },
        crack(hit) {
          g.res.cracks += 1;
          g.snd('fail');
          g.flash('bad', T('c3_crack', 'You pressed on it while it was setting: the plaster cracked.'), 2200);
          g.addCrack(hit.s, hit.a);
        },
        mould() { let a = 0; for (let i = 0; i < CELLS; i++) a += Math.min(1.1, g.mouldM[i]); return a / CELLS; },
        minM() { let m = Infinity; for (let i = 0; i < CELLS; i++) m = Math.min(m, g.mouldM[i]); return m; },
        // over-worked (dented) share: rubbing one spot long past smooth pushes the result over the band
        over() { let a = 0; for (let i = 0; i < CELLS; i++) a += Math.max(0, g.mouldM[i] - 1); return a / CELLS; },
        result() { return clamp(this.mould() + this.over(), 0, 1.25); },
        toSetting(timeUp) {
          this.phase = 'setting';
          g.res.mould = this.result();
          g.useHand(null);
          const ok = g.res.mould >= 0.62 && g.res.mould <= 0.86;
          if (timeUp) g.flash('warn', T('c3_mould_late', 'The plaster started to set before you finished moulding.'), 2400);
          else g.flash(ok ? 'ok' : 'warn', ok ? T('mould_ok', 'Nicely moulded. Keep still while it sets.') : T('c3_mould_off', 'Moulding is uneven. Hands off while it sets.'), 2400);
          g.pp.set({ title: T('c3_p_set', 'Let it set'), text: T('c3_p_set_t', '**Hands off.** Do not press on the cast while the plaster sets.'), hints: g.hintsFor([]) });
          g.snd('success');
        },
        tick(dt) {
          if (this.phase === 'mould') {
            this.work = Math.max(0, this.work - dt);
            const c = this.contact();
            if (c) { hs.s = lerp(hs.s, c.s, hs.ok ? 1 - Math.exp(-dt * 25) : 1); hs.a = lerp(hs.a, c.a, hs.ok ? 1 - Math.exp(-dt * 25) : 1); hs.ok = true; }
            hs.press = lerp(hs.press, g.lmb && c ? 1 : 0, 1 - Math.exp(-dt * 14));
            if (g.lmb && c) this.rub(c); else if (!g.lmb) this.last = null;
            if (hs.ok) g.placeMouldHand(hs.s, hs.a, hs.press);
            this.layT = (this.layT || 0) - dt;
            if (this.dirty && this.layT <= 0) { this.dirty = false; this.layT = 0.1; g.layShell(this.dLo, this.dHi); }
            // the weave fills in as it is moulded
            const m = this.mould();
            g.M.plaster.normalScale.setScalar(lerp(0.75, 0.25, clamp(m, 0, 1)));
            if ((m > 0.86 || this.over() > 0.02) && !this.overWarned) { this.overWarned = true; g.flashOnce('warn', T('c3_mould_over', 'Too much: you are denting it. Spread it out.'), 2000); }
            g.stageCursor(c ? 'hide' : '');
            if (m >= 0.62 && this.minM() >= MOULD_TOUCH) { this.toSetting(false); return; }
            if (this.work <= 0) { this.toSetting(true); return; }
            // progress: the mean toward the band, held back while sections are still untouched
            const even = Array.from(g.mouldM).filter(x => x >= MOULD_TOUCH).length / CELLS, p = clamp(m / 0.62, 0, 1) * (0.6 + 0.4 * even);
            if (g.lmb && c) g.cursor(p, m >= 0.5 && even < 1 ? T('c3_cap_mould', 'Rub it all, end to end') : T('c3_cur_mould', 'Smoothing…'), m > 0.86 ? 'red' : 'teal');
            else g.cursor(c ? p : null, c ? T('c3_cur_rub', 'Hold LMB and rub') : '', '');
            return;
          }
          if (this.phase === 'setting') {
            g.stageCursor('');
            // plaster sets: wet gloss → matte chalk (the finish waits for the server's minimum time)
            this.setting = Math.min(1, this.setting + dt / SET_TIME);
            const f = this.setting, M = g.M.plaster;
            M.roughness = lerp(0.5, 0.92, f); M.clearcoat = lerp(0.55, 0.02, f); M.color.setRGB(lerp(0.86, 0.96, f), lerp(0.855, 0.955, f), lerp(0.83, 0.93, f));
            g.cursor(null, '', '');
            if (f >= 1 && !this.finished) g.stepDone(T('c3_ok_set', 'The cast has set: hard and smooth.'));
          }
        },
        exit() {
          if (this.phase === 'mould') { g.res.mould = this.result(); }
          g.useHand(null);
          const M = g.M.plaster; M.roughness = 0.92; M.clearcoat = 0.02; M.color.setRGB(0.96, 0.955, 0.93);
        },
        panel() {
          if (this.phase === 'mould') {
            const m = this.mould(), even = Array.from(g.mouldM).filter(x => x >= MOULD_TOUCH).length / CELLS;
            g.pp.set({
              stats: [
                { id: 'work', label: T('c3_st_work', 'Working time'), value: `0:${String(Math.ceil(this.work)).padStart(2, '0')}`, tone: this.work < 8 ? 'amber' : '' },
                { id: 'even', label: T('even', 'Even'), value: String(Math.round(even * 100)), unit: '%', meter: { value: even } },
              ],
              wide: { label: T('mould', 'Mould'), value: String(Math.round(m * 100)), unit: '%', tone: m > 0.86 ? 'red' : '', meter: { value: clamp(m, 0, 1), zone: [0.62, 0.86] }, caption: T('c3_cap_mould', 'Rub it all, end to end'), captionTone: 'teal' },
            });
          } else {
            g.pp.set({
              stats: [{ id: 'ml', label: T('mould', 'Mould'), value: String(Math.round(g.res.mould * 100)), unit: '%', tone: g.res.mould >= 0.62 && g.res.mould <= 0.86 ? 'teal' : 'amber' }, { id: 'cr', label: T('cracks', 'Cracks'), value: String(g.res.cracks), tone: g.res.cracks ? 'red' : '' }],
              wide: { label: T('setting', 'Setting'), value: String(Math.round(this.setting * 100)), unit: '%', meter: { value: this.setting }, caption: T('c3_cap_set', 'Hands off'), captionTone: 'teal' },
            });
          }
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 6. FOLD THE STOCKINETTE ENDS ═════════════════════════════
       Each cuff (past the padding edge) is turned back like the cuff of a sock: f 0 → 1. The free end
       curls over first, the rolled edge travels in to the cast edge, and the turned layer (inside out)
       lies back over the cuff and then drapes over the edge of the cast. u = the knit's own coordinate
       from the hinge (the padding edge), so the texture stays with the fabric. */
    castOuter(s, a, o) {
      // the cast surface softened toward its edge (seen from the cuff side): the knit drapes over the
      // step of the plaster edge instead of standing up as a wall
      return Math.max(this.under(s, a), this.under(s - o * 0.003, a) - 0.0015, this.under(s - o * 0.006, a) - 0.003) + 0.0008;
    }
    layFold(pt) {
      const st = this.stk, NAs = st.NAs, P = new THREE.Vector3(), o = pt.o;
      const hingeS = o < 0 ? st.sPe : st.sDe, len = Math.abs(o < 0 ? st.sPe - st.sE : st.s0 - st.sDe);
      const f = smooth(0, 1, pt.fold), m = f * len;   // knit turned back so far
      const sf = hingeS + o * (len - m);              // the rolled edge
      const pos = pt.geo.attributes.position.array, hint = pt.hint || (pt.hint = new Float32Array((pt.rows + 1) * 3));
      const rSkin = (s, a) => this.R + this.skinH(s, a) + STK * 0.8;
      // the roll is a couple of knit thicknesses; at the end it has to reach from the skin up onto the cast
      const sIn = hingeS - o * 0.012, rho0 = 0.0022, rhoEnd = smooth(0.55, 1, f);
      const rhoA = new Float32Array(NAs + 1);
      for (let i = 0; i <= NAs; i++) { const a = (i / NAs) * TAU - Math.PI; rhoA[i] = lerp(rho0, Math.max(rho0, (this.castOuter(sIn, a, o) - rSkin(hingeS, a)) / 2), rhoEnd); }
      let sEnd = sf, rEnd = 0;
      for (let j = 0; j <= pt.rows; j++) {
        const u = Math.abs(lerp(pt.a, pt.b, j / pt.rows) - hingeS), w = u - (len - m);
        for (let i = 0; i <= NAs; i++) {
          const a = (i / NAs) * TAU - Math.PI, k = j * (NAs + 1) + i, rho = rhoA[i];
          let s, r, part, psi = 0;
          if (w <= 0) { s = hingeS + o * u; r = rSkin(s, a); part = 0; }          // still flat on the skin
          else if (w <= Math.PI * rho) {                                           // round the rolled edge
            psi = -Math.PI / 2 + w / rho;
            s = sf + o * rho * Math.cos(psi); r = rSkin(sf, a) + rho + rho * Math.sin(psi); part = 1;
          } else {                                                                 // turned back over the cuff / the cast
            s = sf - o * (w - Math.PI * rho);
            r = Math.max(rSkin(s, a) + 2 * rho, this.castOuter(s, a, o)); part = 2;
          }
          this.cyl(s, a, r, P);
          pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
          // the knit's front face: outward on the skin, round the roll, inward once turned (inside out);
          // the DoubleSide shader flips what is seen from the back, so the turned layer lights from outside
          if (i === 0) { hint[j * 3] = part; hint[j * 3 + 1] = psi; }
          if (j === pt.rows && i === NAs / 2) { sEnd = s; rEnd = r; }
        }
      }
      gridNormals(pt.geo, NAs, pt.rows, k => {
        const j = Math.floor(k / (NAs + 1)), a = ((k % (NAs + 1)) / NAs) * TAU - Math.PI, c = Math.cos(a), sn = Math.sin(a);
        const part = hint[j * 3], psi = hint[j * 3 + 1];
        if (part === 0) return [0, c, sn];
        if (part === 2) return [0, -c, -sn];
        return [-o * Math.cos(psi), -Math.sin(psi) * c, -Math.sin(psi) * sn];
      });
      pt.geo.computeBoundingSphere();
      // the hem follows the cuff's open end
      const hem = o < 0 ? st.hems[1] : st.hems[0];
      const rHem = Math.max(this.R, rEnd + 0.0003);
      hem.visible = true; hem.rotation.set(0, Math.PI / 2, 0); hem.position.set(sEnd, -this.R, 0); hem.scale.set(rHem, rHem, 1);
    }
    phFold() {
      const g = this, st = this.stk;
      this.frameStep('fold');
      const flaps = [st.parts[0], st.parts[2]];
      const pinAt = pt => { const hs = pt.o < 0 ? st.sE : st.s0; return g.S.stToUv(hs - pt.o * 0.006, g.R * 0.35); };
      flaps.forEach((pt, i) => { g.S.markers.set(`fold${i}`, { uv: pinAt(pt), kind: 'pin', size: 0.016, color: 0x0fd4c4, pulse: true }); });
      const ph = {
        grab: null, done: 0, anim: [],
        hints: [{ keys: [T('c3_k_drag', 'Drag')], label: T('c3_h_fold', 'fold an end over the edge') }],
        panelInit() { return { title: T('c3_p_fold', 'Fold the ends back'), text: T('c3_p_fold_t', '**Drag each stockinette end** in over the edge of the cast (the teal markers), so no rough plaster edge touches the skin.') }; },
        // which cuff is under / nearest the cursor
        pick() {
          let best = null, bd = Infinity;
          flaps.forEach(pt => {
            if (pt.fold >= 1) return;
            const hs = pt.o < 0 ? st.sE : st.s0, P = g.cyl(hs - pt.o * 0.006, 0.35, g.R + 0.004);
            const d = g.pxTo(P);
            if (d < bd) { bd = d; best = pt; }
          });
          const hit = g.pickCyl(g.R + 0.006);
          if (hit) flaps.forEach(pt => { if (pt.fold < 1 && (pt.o < 0 ? hit.s < st.sPe + 0.01 : hit.s > st.sDe - 0.01)) best = pt; });
          return (hit && best) || bd < Math.max(110, window.innerHeight * 0.12) ? best : null;
        },
        curS() { return g.sAtPointer(0.35, g.R + 0.006); },
        down() {
          const pt = this.pick();
          if (!pt) { g.flashOnce('warn', T('c3_fold_here', 'Grab an end of the stockinette (the teal markers).'), 1600); return; }
          this.grab = { pt, s0: this.curS(), f0: pt.fold };
          g.click(540);
        },
        pointer() {
          const gb = this.grab;
          if (!gb || !g.lmb) return;
          const pt = gb.pt, len = Math.abs(pt.o < 0 ? st.sPe - st.sE : st.s0 - st.sDe);
          // dragging inward (toward the cast) folds it: a full fold = twice the cuff length
          const f = clamp(gb.f0 + (-(this.curS() - gb.s0) * pt.o) / (len * 1.6), 0, 1);
          if (Math.abs(f - pt.fold) > 1e-4) { pt.fold = f; g.layFold(pt); }
        },
        up() {
          const gb = this.grab;
          if (!gb) return;
          this.pointer();
          this.grab = null;
          const pt = gb.pt;
          this.anim.push({ pt, to: pt.fold >= 0.4 ? 1 : 0 });
          if (pt.fold < 0.4 && pt.fold > 0.05) g.flashOnce('warn', T('c3_fold_more', 'Pull it further: right over the edge of the cast.'), 1600);
        },
        tick(dt) {
          if (this.grab && g.lmb) this.pointer();
          for (let i = this.anim.length - 1; i >= 0; i--) {
            const an = this.anim[i], pt = an.pt;
            pt.fold = an.to > pt.fold ? Math.min(1, pt.fold + dt * 3) : Math.max(0, pt.fold - dt * 4);
            g.layFold(pt);
            if (pt.fold === an.to) {
              this.anim.splice(i, 1);
              if (an.to === 1) { g.click(760); g.S.markers.remove(`fold${flaps.indexOf(pt)}`); }
            }
          }
          const n = flaps.filter(p => p.fold >= 1).length;
          if (n >= 2 && !this.finished) { g.stepDone(T('c3_ok_fold', 'Both ends folded back: smooth edges.')); return; }
          if (this.finished) return;
          const gb = this.grab;
          const hover = !gb && this.pick();
          g.stageCursor(gb ? 'grabbing' : hover ? 'grab' : '');
          if (gb) g.cursor(gb.pt.fold, T('c3_cur_fold', 'Over the edge…'), gb.pt.fold >= 0.4 ? 'teal' : '');
          else g.cursor(null, hover ? T('c3_cur_fold_hint', 'Drag it in over the cast') : '', '');
        },
        exit() { flaps.forEach((pt, i) => { pt.fold = 1; g.layFold(pt); g.S.markers.remove(`fold${i}`); }); },
        panel() {
          const n = flaps.filter(p => p.fold >= 1).length;
          g.pp.set({
            stats: [{ id: 'ends', label: T('c3_st_ends', 'Ends'), value: `${n}/2` }],
            wide: { label: T('c3_w_fold', 'Folded'), value: `${n}/2`, meter: { value: n / 2, segs: true }, caption: T('c3_cap_fold', 'No rough edges on the skin'), captionTone: 'teal' },
          });
        },
      };
      return ph;
    }

    /* ═════════════════════════════ 7. CMS CHECK ═════════════════════════════ */
    phCms() {
      const g = this, S = this.S;
      this.frameStep('cms');
      const st = this.stk, s = st.s0 + 0.012, a = 0.3;
      const uv = S.stToUv(s, a * this.R);
      S.markers.set('cms', { uv, kind: 'dashed', size: 0.024, color: 0x0fd4c4, pulse: true });
      this.useHand('point');
      const digits = this.leg ? T('c3_toes', 'toes') : T('c3_fingers', 'fingers');
      const ph = {
        phase: 'press', hold: 0, refill: 0, after: 0, c: false, m: false, s: false,
        hints: [{ keys: [T('c3_k_lmb', 'Hold LMB')], label: T('c3_h_cms', 'press the skin, let go') }],
        panelInit() { return { title: T('c3_p_cms', 'Check circulation'), text: T('c3_p_cms_t', '**Press and hold** the skin past the cast (teal ring) for a second, then **let go**: it must turn pink again within 2 s. Then check they can move and feel their %s.', digits) }; },
        onSpot() { const hit = S.tools.hit; return !!hit && S.distanceUv(hit.uv, uv) < 0.016; },
        down() {
          if (this.phase !== 'press') return;
          if (!this.onSpot()) { g.flashOnce('warn', T('c3_cms_here', 'Press on the skin inside the teal ring.'), 1500); return; }
          this.pressing = true;
        },
        up() {
          if (this.phase !== 'press' || !this.pressing) return;
          this.pressing = false;
          S.tools.press(false);
          if (this.hold >= 0.8) { this.phase = 'refill'; this.refill = 0; g.click(700); S.markers.remove('cms'); }
          else if (this.hold > 0.05) g.flashOnce('warn', T('c3_cms_short', 'Hold it a moment longer, until the ring fills.'), 1500);
          this.hold = 0;
        },
        tick(dt) {
          const bl = g.blanch;
          if (this.phase === 'press') {
            const on = this.pressing && g.lmb && this.onSpot();
            S.tools.press(!!(this.pressing && g.lmb));
            if (on) this.hold = Math.min(1.2, this.hold + dt); else if (!g.lmb) this.hold = 0;
            const hit = S.tools.hit;
            if (on && hit) {
              bl.visible = true;
              bl.position.copy(hit.point).addScaledVector(hit.normal, 0.0004);
              bl.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), hit.normal);
              bl.scale.setScalar(0.0075);
              g.M.blanch.color.copy(g.blanchColor());
              g.M.blanch.opacity = 0.75 * clamp(this.hold / 0.5, 0, 1);
            } else if (this.phase === 'press') { g.M.blanch.opacity = Math.max(0, g.M.blanch.opacity - dt * 2); }
            g.stageCursor(S.tools.hit ? 'hide' : '');
            if (on) g.cursor(clamp(this.hold / 0.8, 0, 1), this.hold >= 0.8 ? T('c3_cur_letgo', 'Let go') : T('c3_cur_press', 'Pressing…'), 'teal');
            else g.cursor(null, this.onSpot() ? T('c3_cur_cms', 'Hold LMB') : '', '');
            return;
          }
          if (this.phase === 'refill') {
            this.refill += dt;
            g.M.blanch.opacity = 0.75 * clamp(1 - this.refill / 1.3, 0, 1);
            g.cursor(null, '', '');
            if (this.refill >= 1.4 && !this.c) { this.c = true; g.useHand(null); g.flash('ok', T('c3_cms_c', 'Pink again in about 1.5 s: circulation is fine.'), 1800); g.click(760); }
            if (this.refill >= 2.6 && !this.m) { this.m = true; g.flash('ok', T('c3_cms_m', 'They move their %s: motor fine.', digits), 1600); g.click(780); g.S.controls.shake(0.06, 300); }
            if (this.refill >= 3.8 && !this.s) { this.s = true; g.flash('ok', T('c3_cms_s', '"Yes, I can feel that." Sensation fine.'), 1800); g.click(800); }
            if (this.refill >= CMS_END && !this.finished) { bl.visible = false; g.stepDone(T('c3_ok_cms', 'CMS checked: circulation, movement and feeling all fine.')); }
          }
        },
        // (carrying on) the press was done r s ago: the refill check runs on from there
        toRefill(r) {
          this.phase = 'refill'; this.refill = r; this.pressing = false; this.hold = 0;
          S.tools.press(false); S.markers.remove('cms');
          this.c = r >= 1.4; this.m = r >= 2.6; this.s = r >= 3.8;
          if (this.c) g.useHand(null);
          const bl = g.blanch, hit = r < 1.3 ? S.surfaceAt(uv) : null;
          if (hit && hit.point && hit.normal) {
            bl.visible = true;
            bl.position.copy(hit.point).addScaledVector(hit.normal, 0.0004);
            bl.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), hit.normal);
            bl.scale.setScalar(0.0075);
            g.M.blanch.color.copy(g.blanchColor());
            g.M.blanch.opacity = 0.75 * clamp(1 - r / 1.3, 0, 1);
          } else { bl.visible = false; g.M.blanch.opacity = 0; }
        },
        exit() { S.markers.remove('cms'); g.useHand(null); g.blanch.visible = false; },
        panel() {
          const mk = (id, l, on) => ({ id, label: l, value: on ? T('c3_ok', 'OK') : '--', tone: on ? 'teal' : '' });
          g.pp.set({
            stats: [mk('c', T('c3_st_c', 'Circulation'), this.c), mk('m', T('c3_st_m', 'Motor'), this.m), mk('s', T('c3_st_s', 'Sensation'), this.s)],
            wide: { label: T('c3_w_refill', 'Cap refill'), value: this.c ? '1.5' : '--', unit: this.c ? 's' : '', meter: { value: this.phase === 'press' ? clamp(this.hold / 0.8, 0, 1) : 1 }, caption: T('c3_cap_refill', 'Under 2 seconds'), captionTone: 'teal' },
          });
        },
      };
      return ph;
    }
    blanchColor() {
      const t = this.S.skin && this.S.skin.toneRGB;
      const c = t ? new THREE.Color(t[0] !== undefined ? t[0] : t.r, t[1] !== undefined ? t[1] : t.g, t[2] !== undefined ? t[2] : t.b) : new THREE.Color(0.85, 0.66, 0.55);
      return c.lerp(new THREE.Color(1, 0.96, 0.92), 0.45);
    }
    // a hairline crack where the setting cast was pressed (its own seeded wobble: a restored crack is drawn
    // again the same)
    addCrack(s0, a0) {
      const k = this.crackList.length, r = rng(((this.seed >>> 0) ^ Math.imul(k + 1, 0x9E3779B1)) >>> 0);
      this.crackList.push({ s: s0, a: a0 });
      const pts = [];
      let s = s0 - 0.012, a = a0 - 0.04;
      for (let i = 0; i < 7; i++) { pts.push(this.cyl(s, a, this.under(s, a) + 0.0004)); s += 0.004; a += (r() - 0.5) * 0.06 + 0.012; }
      const geo = this.keep(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 24, 0.0004, 4, false));
      const m = new THREE.Mesh(geo, this.M.crack); m.renderOrder = 5;
      this.S.scene.add(m);
    }

    /* ─────────────── finish: the same result as the 2D game ─────────────── */
    finish() {
      if (this.finished) return;
      this.finished = true;
      if (this.pp) this.pp.set({ pause: false });   // nothing left to step away from
      if (this.ph && this.ph.exit) this.ph.exit();
      this.ph = { name: 'done', panel() {}, tick() {} };
      this.useHand(null);
      this.cursor(null, '');
      this.stageCursor('');
      this.frameStep('done');
      const mn = this.layerMin(), mx = this.layerMax(), minL = this.minL, maxL = this.maxL;
      const good = Array.from(this.layers).filter(n => n >= minL && n <= maxL).length / CELLS;
      const padQ = this.res.padQ.length ? this.res.padQ.reduce((a, b) => a + b, 0) / this.res.padQ.length : 0.7;
      const padCov = 0.5 * (this.padLayers.filter(x => x >= 1).length / CELLS) + 0.5 * padQ;
      const mould = this.res.mould;
      const mouldOk = mould >= 0.62 && mould <= 0.86 ? 1 : mould < 0.62 ? mould / 0.62 : clamp(1 - (mould - 0.86) * 3, 0, 1);
      let score = 10 * padCov + 45 * good + 20 * mouldOk + 25 * clamp(1 - Math.max(0, mx - maxL) * 0.15 - Math.max(0, minL - mn) * 0.2, 0, 1) - this.res.cracks * 10;
      score = Math.round(clamp(score, 0, 100));
      // (mould posted in the 2D game's range, 0–110 %: the score above already counted any over-moulding)
      const result = { score, coverage: Math.round(good * 100), layersMin: Math.round(mn * 10) / 10, layersMax: Math.round(mx * 10) / 10, cracks: this.res.cracks, mould: Math.round(clamp(mould, 0, 1.1) * 100) };
      this.result = result;
      this.pp.set({ title: T('saving', 'Saving...'), text: '', tools: [], stats: [], wide: null, hints: this.hintsFor([]) });
      // never before the server's minimum procedure time
      const wait = Math.max(0, MIN_TIME * 1000 - (performance.now() - this.openAt));
      setTimeout(() => {
        if (!this.alive) return;
        this.ctx.post('finish', result);
        if (!NZA.inGame) setTimeout(() => { if (this.alive) this.showResult({ score, grade: score >= 85 ? 'A' : score >= 72 ? 'B' : 'C', msg: `${this.castName} applied${this.leg ? ' · Recommend crutches' : ''}` }); }, 400);
      }, wait);
    }
    showResult(r) {
      if (this.shown) return;
      this.shown = true;
      const res = this.result || {}, good = (res.coverage || 0) / 100, mould = (res.mould || 0) / 100;
      this.ctx.resultCard(r, [
        [T('coverage', 'Coverage'), `${Math.round(good * 100)}%`, good > 0.8 ? 'ok' : 'warn'],
        [T('cracks', 'Cracks'), res.cracks || 0, res.cracks ? 'bad' : 'ok'],
        [T('mould', 'Mould'), `${Math.round(mould * 100)}%`, mould >= 0.62 && mould <= 0.86 ? 'ok' : 'warn'],
      ]);
    }

    /* ═════════════════════════════ step away / carry on ═════════════════════════════
       snapshot() → a small JSON-safe object, or null while a move is half done. The next open of the same
       procedure on the same fracture carries it back as data.resume; boot() → restore() rebuilds that point
       on the fresh scene (built from the fresh open data) by running the steps through again. */
    snapshot() {
      const ph = this.ph;
      if (!this.ready || !this.alive || !this.S || this.finished || this.restoring || !ph) return null;
      const at = this.stepIdx, name = ph.name;
      if (STEPS[at] !== name) return null;
      // finish the move first: a roll or a cuff in the hand, the palm rubbing, the plaster roll held, a press
      // on the skin (holding on the setting cast is no move: the crack is made when it is pressed)
      const setting = name === 'mould' && ph.phase === 'setting';
      if ((this.lmb && !setting) || ph.grab || ph.held || ph.pressing) return null;
      // the last check is done: the result is being saved
      if (name === 'cms' && ph.finished) return null;
      const st = this.stk;
      const snap = {
        v: 1,
        w: { inj: String(this.d.injury === undefined || this.d.injury === null ? '' : this.d.injury), reg: String(this.d.region || ''), seed: this.seed >>> 0 },
        step: at, el: rnd(clamp((performance.now() - this.openAt) / 1000, 0, MAX_EL), 1), t: rnd(clamp(this.t, 0, 1e6), 2),
        // 1 · how far the stockinette is rolled on (where the roll is heading)
        stk: st.done || at > 0 ? 1 : rnd(clamp((st.s0 - Math.min(st.ring, st.target)) / (st.s0 - st.sE), 0, 0.9999), 4),
      };
      // 2 · padding / 4 · plaster: the centre of every turn laid by hand + the turn being rolled on
      if (at >= 1) snap.pad = this.wrapSnap(this.wPad, at === 1 ? ph : null);
      // 3 · dip: how soaked, and whether it lies in the water (lifting out: soaked)
      if (at >= 2) snap.dip = at > 2 || ph.lifting || ph.soak >= 1 ? { s: 1, w: 0 } : { s: Math.floor(clamp(ph.soak, 0, 1) * 1000) / 1000, w: ph.inWater ? 1 : 0 };
      if (at >= 3) snap.pl = this.wrapSnap(this.wPl, at === 3 ? ph : null);
      // 5 · mould: every section, the working time left, setting or not and how far, the cracks
      if (at >= 4) {
        const m4 = at === 4 ? ph : null;
        snap.ml = {
          m: Array.from(this.mouldM, v => rnd(v, 4)), wk: m4 ? rnd(clamp(m4.work, 0, WORK_TIME), 2) : 0, ph: !m4 || m4.phase === 'setting' ? 1 : 0,
          set: !m4 || m4.setting >= 1 ? 1 : Math.floor(clamp(m4.setting, 0, 1) * 1000) / 1000, ow: m4 && m4.overWarned ? 1 : 0,
        };
        snap.cr = this.crackList.map(c => [rnd(c.s, 5), rnd(c.a, 4)]);
      }
      // 6 · fold: each stockinette end (one easing over or back: where it is going)
      if (at >= 5) {
        snap.fold = [st.parts[0], st.parts[2]].map(pt => {
          if (at > 5) return 1;
          const an = (ph.anim || []).find(x => x.pt === pt);
          return an ? an.to : rnd(clamp(pt.fold, 0, 1), 3);
        });
      }
      // 7 · cms: still to press (-1) or how far the refill check has run
      if (at >= 6) snap.cms = { r: ph.phase === 'refill' ? Math.floor(clamp(ph.refill, 0, CMS_END - 0.01) * 100) / 100 : -1 };
      return snap;
    }
    wrapSnap(w, ph) {
      const c = w ? w.turns.filter(t => !t.anchor && t.passStamped).map(t => rnd(t.C, 6)) : [];
      const t = ph && ph.turn;
      const cur = t && (ph.phase === 'wait' || ph.phase === 'drag') && !t.anchor && !t.passStamped ? [rnd(t.C, 6), rnd(clamp(t.phi, 0, PASS - 0.002), 4)] : null;
      return { c, cur };
    }
    // which fracture a snapshot was taken on: 'same', 'other' (another injury / limb / patient) or 'bad'
    limbMatch(snap) {
      const w = snap.w;
      if (snap.v !== 1 || !plain(w)) return 'bad';
      const d = this.d, inj = d.injury === undefined || d.injury === null ? '' : String(d.injury);
      const same = String(w.inj === undefined || w.inj === null ? '' : w.inj) === inj && String(w.reg || '') === String(d.region || '') && num(w.seed, -1) === (this.seed >>> 0);
      return same ? 'same' : 'other';
    }
    // Rebuild the saved point → the step it opens on. Every step runs through the game's own step machine
    // (enter → its saved state → done → the next), so what follows from what is on the limb (the bands,
    // layer counts, overlap scores, the moulded shell, the mould result) is worked out again, not read. A
    // step is entered only when every step before it is done; data of a step later than the one the
    // snapshot was on is never read; an unreadable / out-of-range field starts its own step over.
    restore(r) {
      const at0 = intIn(r.step, 0, STEPS.length - 1), AT = at0 === null ? 0 : at0;
      const el = numIn(r.el, 0, MAX_EL), t = numIn(r.t, 0, 1e6);
      if (el !== null) this.openAt = performance.now() - el * 1000;
      if (t !== null) this.t = t;
      const go = name => { this.stepIdx = STEPS.indexOf(name); this.enter(name); return this.ph; };
      const end = name => { this.frameStep(name, true); this.updateTools(); if (this.ph.panel) this.ph.panel(); return name; };
      const st = this.stk;

      // 1 · stockinette
      let ph = go('stockinette');
      const sp = numIn(r.stk, 0, 1);
      if (sp !== null) {
        st.ring = st.target = sp >= 1 ? st.sE : st.s0 - sp * (st.s0 - st.sE);
        if (st.ring <= st.sE + 0.0015) { st.ring = st.target = st.sE; st.done = true; ph.finished = true; }
        this.layStock();
      }
      if (!st.done) return end('stockinette');

      // 2 · padding
      ph = go('padding');
      if (AT >= 1 && !this.replayWrap(ph, r.pad, AT === 1)) ph = this.resetWrap(true);
      if (ph.phase !== 'done') return end('padding');

      // 3 · dip
      ph = go('dip');
      let soaked = false;
      if (AT >= 2) {
        const D = plain(r.dip) ? r.dip : null, s = D ? numIn(D.s, 0, 1) : null, w = D ? bit(D.w) : -1;
        if (s !== null && w >= 0) {
          if (s >= 1) soaked = true;
          else { ph.soak = s; if (w === 1) ph.sink(); }
        }
      }
      if (!soaked) return end('dip');
      // lifted out soaked (as lift() leaves it)
      ph.soak = 1; ph.finished = true;
      this.plRoll.inner.children[0].material = this.M.plaster;
      this.basin.milk = Math.min(1, this.basin.milk + 0.5);
      this.wet = 1; this.dripOn = true;

      // 4 · plaster
      ph = go('plaster');
      if (AT >= 3 && !this.replayWrap(ph, r.pl, AT === 3)) ph = this.resetWrap(false);
      if (ph.phase !== 'done') return end('plaster');

      // 5 · mould and set
      ph = go('mould');
      let set = false;
      if (AT >= 4) {
        const M = plain(r.ml) ? r.ml : null, m = M ? list(M.m) : null, cr = list(r.cr);
        const wk = M ? numIn(M.wk, 0, WORK_TIME) : null, mp = M ? bit(M.ph) : -1, sf = M ? numIn(M.set, 0, 1) : null, ow = M ? bit(M.ow) : -1;
        const mOk = !!m && m.length === CELLS && m.every(x => numIn(x, 0, 1.25) !== null);
        const crOk = !!cr && cr.length <= 50 && cr.every(c => Array.isArray(c) && c.length === 2 && numIn(c[0], this.sP - 0.006, this.sD + 0.006) !== null && numIn(c[1], -3.15, 3.15) !== null);
        // (setting progress and cracks only once it sets: while it is moulded nothing has set yet)
        if (mOk && crOk && wk !== null && mp >= 0 && sf !== null && ow >= 0 && (mp === 1 || (sf === 0 && !cr.length))) {
          m.forEach((x, i) => { this.mouldM[i] = +x; });
          this.layShell();
          ph.work = wk; ph.overWarned = ow === 1;
          this.M.plaster.normalScale.setScalar(lerp(0.75, 0.25, clamp(ph.mould(), 0, 1)));
          if (mp === 1) {
            ph.toSetting(wk <= 0);
            ph.setting = sf;
            cr.forEach(c => this.addCrack(+c[0], +c[1]));
            this.res.cracks = this.crackList.length;
            set = sf >= 1;
          }
        }
      }
      if (!set) return end('mould');
      ph.finished = true;

      // 6 · fold the ends
      ph = go('fold');
      if (AT >= 5) {
        const F = list(r.fold);
        if (F && F.length === 2 && F.every(f => numIn(f, 0, 1) !== null)) {
          [st.parts[0], st.parts[2]].forEach((pt, i) => { pt.fold = +F[i]; this.layFold(pt); if (pt.fold >= 1) this.S.markers.remove(`fold${i}`); });
        }
      }
      if (!(st.parts[0].fold >= 1 && st.parts[2].fold >= 1)) return end('fold');
      ph.finished = true;

      // 7 · CMS
      ph = go('cms');
      if (AT >= 6) {
        const C = plain(r.cms) ? r.cms : null, rf = C ? num(C.r, NaN) : NaN;
        if (rf >= 0 && rf < CMS_END) ph.toRefill(rf);
      }
      return end('cms');
    }
    // play a wrap step through again from the centres of the turns laid by hand: the game's own machine lays
    // the anchor turns, starts each pass and ends the wrap, each turn on the last as in play
    // → false: not a wrap this game could have laid (the caller takes it off and starts the step over)
    replayWrap(ph, W, withCur) {
      if (!plain(W)) return false;
      const cs = list(W.c);
      if (!cs || cs.length > MAX_TURNS || !cs.every(c => Number.isFinite(num(c, NaN)))) return false;
      const bw = ph.w.bw;
      // (a centre a player can lay: 15 % to a whole band past the last turn, never past the end of the pass)
      const fits = (C, t) => !!t && !!t.prev && Math.abs(ph.clampC(C, t.prev.C) - C) <= 2e-5;
      let i = 0;
      ph.tick(0);                       // the first pass and its anchor turn
      for (let guard = 0; guard < 4 * MAX_TURNS && ph.phase !== 'done'; guard++) {
        const t = ph.turn;
        if (ph.phase === 'anchor') {
          // up to the end of its visible pass (stamped there), then round underneath: as play lays it
          if (!t.passStamped) { ph.animT = 0.7 * (PASS + 1e-6) / TAU; ph.tick(0); }
          ph.animT = 1e3; ph.tick(0);
        } else if (ph.phase === 'round') { ph.animT = 1e3; ph.tick(0); }
        else if (ph.phase === 'wait' || ph.phase === 'drag') {
          if (i >= cs.length) break;      // the next turn was not laid yet
          const C = +cs[i++];
          if (!fits(C, t)) return false;
          ph.nudge = C - ph.ideal; ph.drift = 0; ph.applyC();
          this.growTurn(t, PASS); ph.endPass();
        } else return false;
      }
      if (i < cs.length) return false;   // turns left over: not this wrap
      const cur = W.cur;
      if (cur === null || cur === undefined) return ph.phase === 'done' || ph.phase === 'wait';
      // the turn that was being rolled on: its centre and how far up it was
      if (!withCur || !Array.isArray(cur) || cur.length !== 2 || ph.phase !== 'wait') return false;
      const C = num(cur[0], NaN), phi = numIn(cur[1], 0, PASS - 1e-3), t = ph.turn;
      if (!Number.isFinite(C) || phi === null || !fits(C, t)) return false;
      ph.nudge = clamp(C - ph.ideal, -bw, bw); ph.drift = 0; ph.applyC();
      if (phi > 1e-4) { this.growTurn(t, phi); ph.target = phi; if (phi > 0.02) ph.phase = 'drag'; }
      this.rollAt(ph.w, t, ph.roll);
      return true;
    }
    // a wrap that did not replay cleanly: take it off again (its bands, thickness, layer counts and scores)
    // and open that step from its start
    resetWrap(isPad) {
      const w = isPad ? this.wPad : this.wPl;
      if (w) w.turns.forEach(t => { this.S.scene.remove(t.mesh); t.geo.dispose(); this.bin.delete(t.geo); });
      (isPad ? this.fPad : this.fPl).fill(0);
      (isPad ? this.padLayers : this.layers).fill(0);
      this.res[isPad ? 'padQ' : 'plQ'] = [];
      if (isPad) this.wPad = null; else this.wPl = null;
      (isPad ? this.padRoll : this.plRoll).group.visible = false;
      this.hideGuide();
      this.ph = null;                    // (no exit: nothing of it is kept)
      this.enter(isPad ? 'padding' : 'plaster');
      return this.ph;
    }
    // a snapshot that could not be rebuilt: open this cast again from the start on a new scene (never a
    // half-rebuilt one), with a note
    restartClean() {
      const ctx = Object.assign({}, this.ctx, { d: Object.assign({}, this.ctx.d) });
      delete ctx.d.resume;
      const holder = this.holder, pp = this.pp;
      this.dispose();
      if (pp && ctx.state.pp === pp) { try { pp.destroy(); } catch (e) { /* gone */ } ctx.state.pp = null; }
      NEXT_NOTE = 'bad';
      let g = null;
      try { g = new Game(ctx, holder); } catch (e) { console.error('[xray] cast restart', e); }
      NEXT_NOTE = null;   // (the new game took it)
      if (!g) { if (ctx.fallback) ctx.fallback(); return; }
      if (holder) holder.g = g;
      Game.current = g;
    }
    // preview only (?resume=<stage>): play to a point in that step the way playing leaves it (no move half
    // done), step away and open again from the snapshot
    previewPark(stage) {
      if (!this.alive || !this.ready || NZA.inGame || this.finished) return;
      const s = String(stage || '').toLowerCase();
      const plan = {
        stockinette: ['stockinette'], padding: ['padding', { turns: 1 }], dip: ['dip'], plaster: ['plaster', { pass: 1, turns: 1 }],
        mould: ['mould'], setting: ['setting', { set: 0.45 }], fold: ['fold'], cms: ['cms'],
      }[s] || ['plaster', { pass: 1, turns: 1 }];
      this.quiet += 1;
      try {
        if (s !== 'stockinette') this.jump(plan[0], plan[1] || {});
        const ph = this.ph;
        if (s === 'stockinette') { const st = this.stk; st.ring = st.target = lerp(st.s0, st.sE, 0.55); this.layStock(); }
        // (the next turn half rolled on)
        if (ph.w && ph.turn && ph.phase === 'wait') { this.growTurn(ph.turn, PASS * 0.5); ph.target = PASS * 0.5; ph.phase = 'drag'; this.rollAt(ph.w, ph.turn, ph.roll); }
        if (s === 'dip') { ph.soak = 0.45; ph.sink(); }
        if (s === 'mould') { for (let i = 0; i < CELLS; i++) this.mouldM[i] = i < 15 ? 0.62 + 0.08 * Math.sin(i * 1.3) : 0.08; this.layShell(); ph.work = 17.5; }
        if (s === 'setting') { this.addCrack(this.sP + (this.sD - this.sP) * 0.68, 0.22); this.res.cracks = this.crackList.length; }
        if (s === 'fold') { const pt = this.stk.parts[2]; pt.fold = 1; this.layFold(pt); this.S.markers.remove('fold1'); }
        if (s === 'cms') ph.toRefill(2);
      } finally { this.quiet -= 1; }
      this.openAt = performance.now() - 96000;
      const snap = this.snapshot();
      if (!snap) return;
      const d = JSON.parse(JSON.stringify(this.ctx.d));
      d.resume = JSON.parse(JSON.stringify(snap));
      NZA.demo('xray', d);
    }
    // the running game's progress (emulator scenarios: XrayCast3D.debug.state())
    debugState() {
      const ph = this.ph || {}, st = this.stk, pz = this.pp && this.pp.el && this.pp.el.querySelector('.pp-pause');
      const wr = w => (w ? w.turns.filter(t => !t.anchor && t.passStamped).map(t => rnd(t.C, 6)) : []);
      const cur = ph.turn && !ph.turn.anchor && !ph.turn.passStamped ? [rnd(ph.turn.C, 6), rnd(ph.turn.phi, 4)] : null;
      const ttl = this.pp && this.pp.el && this.pp.el.querySelector('.pp-title');
      return {
        ready: !!this.ready, alive: !!this.alive, resumed: !!this.resumed, note: this.noteShown || null, finished: !!this.finished,
        idx: this.stepIdx, step: ph.name || null, phase: ph.phase || '', fin: !!ph.finished, lmb: !!this.lmb,
        pause: !!pz && pz.style.display !== 'none', title: ttl ? ttl.textContent : '',
        stk: st ? rnd(clamp((st.s0 - st.ring) / (st.s0 - st.sE), 0, 1), 4) : 0, stkDone: !!(st && st.done),
        pad: wr(this.wPad), padN: this.wPad ? this.wPad.turns.length : 0, padL: Array.from(this.padLayers || []), padQ: this.res.padQ.map(q => rnd(q, 4)),
        pl: wr(this.wPl), plN: this.wPl ? this.wPl.turns.length : 0, layers: Array.from(this.layers || []), plQ: this.res.plQ.map(q => rnd(q, 4)),
        cur: ph.w ? cur : null, pass: ph.pass === undefined ? null : ph.pass,
        soak: ph.soak === undefined ? null : rnd(ph.soak, 3), inWater: !!ph.inWater, milk: this.basin ? this.basin.milk : 0,
        mould: Array.from(this.mouldM || [], v => rnd(v, 4)), work: ph.work === undefined ? null : rnd(ph.work, 2), setting: ph.setting === undefined ? null : rnd(ph.setting, 3),
        resMould: rnd(this.res.mould, 4), cracks: this.res.cracks, crackN: this.crackList.length,
        folds: st ? [rnd(st.parts[0].fold, 3), rnd(st.parts[2].fold, 3)] : [],
        cms: ph.name === 'cms' ? { phase: ph.phase, refill: rnd(ph.refill, 2), c: !!ph.c, m: !!ph.m, s: !!ph.s } : null,
        el: rnd((performance.now() - this.openAt) / 1000, 1), t: rnd(this.t, 2),
      };
    }

    /* ─────────────── preview: open at a stage (index.html?app=xray&mode=cast&stage=…) ─────────────── */
    // opt: the stage's own numbers instead of the page's query (pass, turns, m, set, f)
    jump(stage, opt) {
      if (!this.ready) { this.pendingJump = stage; return; }
      const q = opt ? { get: k => (opt[k] === undefined || opt[k] === null ? null : String(opt[k])) } : new URLSearchParams(location.search);
      const st = String(stage || '').toLowerCase();
      const order = ['stockinette', 'padding', 'dip', 'plaster', 'mould', 'setting', 'fold', 'cms', 'done'];
      const k = order.indexOf(st);
      if (k <= 0) return;
      const at = name => order.indexOf(name) < k;
      // lay everything before the stage the way a steady player would
      const done = name => {
        if (this.ph && this.ph.name === name) return;
        const i = STEPS.indexOf(name);
        if (this.ph && this.ph.exit) this.ph.exit();
        this.stepIdx = i;
        this.ph = null;
        this.enter(name);
      };
      const playWrap = (passes, extraTurns) => {
        const ph = this.ph;
        let guard = 0;
        ph.tick(0.016);
        while (guard++ < 400 && ph.phase !== 'done') {
          if (ph.phase === 'wait' || ph.phase === 'drag') {
            if (passes !== undefined && ph.pass >= passes && (extraTurns || 0) <= 0) break;
            if (passes !== undefined && ph.pass >= passes) extraTurns -= 1;
            ph.ov = 0.5; ph.ovShow = false;
            this.growTurn(ph.turn, PASS); ph.endPass();
          }
          ph.tick(0.25);
        }
      };
      if (at('stockinette') || st === 'padding') {
        done('stockinette');
        this.stk.ring = this.stk.sE; this.stk.target = this.stk.sE; this.stk.done = true; this.layStock();
      }
      if (st === 'padding') { done('padding'); if (q.get('turns')) playWrap(0, +q.get('turns')); return; }
      if (at('padding')) { done('padding'); playWrap(); }
      if (st === 'dip') { done('dip'); return; }
      if (at('dip')) { done('dip'); this.ph.soak = 1; this.plRoll.inner.children[0].material = this.M.plaster; this.wet = 0.2; }
      if (st === 'plaster') { done('plaster'); playWrap(clamp(+(q.get('pass') || 0), 0, 2), +(q.get('turns') || 0)); return; }
      if (at('plaster')) { done('plaster'); playWrap(); }
      if (st === 'mould') { done('mould'); if (q.get('m')) { this.mouldM.fill(clamp(+q.get('m'), 0, 1.2)); this.layShell(); } return; }
      if (at('mould')) {
        done('mould');
        for (let i = 0; i < CELLS; i++) this.mouldM[i] = 0.7 + 0.05 * Math.sin(i);
        this.layShell();
        this.ph.toSetting(false);
      }
      if (st === 'setting') { this.ph.setting = clamp(+(q.get('set') || 0.4), 0, 0.95); return; }
      if (at('setting')) { this.ph.setting = 1; this.ph.tick(0.01); this.ph.finished = true; }
      if (st === 'fold') { done('fold'); if (q.get('f')) { this.stk.parts[2].fold = clamp(+q.get('f'), 0, 1); this.layFold(this.stk.parts[2]); } return; }
      if (at('fold')) { done('fold'); this.ph.exit(); this.ph.finished = true; }
      if (st === 'cms') { done('cms'); return; }
      if (at('cms')) { done('cms'); this.ph.c = this.ph.m = this.ph.s = true; this.ph.exit(); this.ph.finished = true; }
      if (st === 'done') { this.stepIdx = STEPS.length - 1; this.openAt = performance.now() - MIN_TIME * 1000; this.finish(); }
    }

    /* ─────────────── debug / tests: screen positions of things ─────────────── */
    screen(what) {
      const S = this.S, px = P => { const q = S.project(P); return { x: q.x * window.innerWidth, y: q.y * window.innerHeight }; };
      const st = this.stk, R = this.R;
      if (what === 'ring') return px(new THREE.Vector3(st.ring - 0.004, 0.004, 0.012));
      if (what === 'stockEnd') return px(this.cyl(st.sE - 0.02, 0.25, R + 0.006));
      if (what === 'roll') return px(this.basin && this.ph && this.ph.name === 'dip' ? this.plRoll.group.position : this.plRoll.group.position);
      if (what === 'water') return px(new THREE.Vector3(this.basin.x, this.basin.waterY, this.basin.z));
      if (what === 'wrap') {
        // the near side (where the turn starts) and over the far top of the current turn
        const ph = this.ph, t = ph && ph.turn, s = t ? t.C : 0;
        const r = this.under(s, 0.3) + 0.004;
        const a = px(this.cyl(s, 1.55, r)), b = px(this.cyl(s, -0.55, r));
        return { a, b: { x: b.x, y: b.y - window.innerHeight * 0.07 } };
      }
      if (what === 'castL') return px(this.cyl(this.sP + 0.012, 0.2, this.R + 0.012));
      if (what === 'castR') return px(this.cyl(this.sD - 0.012, 0.2, this.R + 0.012));
      if (what === 'castM') return px(this.cyl(0, 0.2, this.R + 0.012));
      if (what === 'foldL') return { a: px(this.cyl(st.sE + 0.004, 0.35, R + 0.004)), b: px(this.cyl(st.sPe + 0.03, 0.35, R + 0.012)) };
      if (what === 'foldR') return { a: px(this.cyl(st.s0 - 0.004, 0.35, R + 0.004)), b: px(this.cyl(st.sDe - 0.03, 0.35, R + 0.012)) };
      if (what === 'cms') return px(S.surfaceAt(S.stToUv(st.s0 + 0.012, 0.3 * R)).point);
      return null;
    }

    /* ─────────────── teardown ─────────────── */
    dispose() {
      if (!this.alive) return;
      this.alive = false;
      const app = this.app;
      window.removeEventListener('blur', this.onBlur);
      window.removeEventListener('resize', this.onResize);
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[xray] cast dispose', e); } this.S = null; }
      this.bin.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } });
      this.bin.clear();
      [this.stage, this.curEl, this.loadEl].forEach(n => { if (n && n.parentNode) n.parentNode.removeChild(n); });
      if (this.pp && this.ctx.state.pp === this.pp && !this.ctx.state.mode) { try { this.pp.destroy(); } catch (e) { /* gone */ } }
      app.full = this.prevApp.full; app.opaque = this.prevApp.opaque;
      if (this.prevApp.camInput === undefined) delete app.camInput; else app.camInput = this.prevApp.camInput;
      if (!app.full) app.el.classList.remove('nza-full');
      if (this.ctx.root) this.ctx.root.querySelectorAll('.xr-root').forEach(n => { n.style.display = ''; });
      this.ph = null;
      if (Game.current === this) Game.current = null;
    }
  }

  window.XrayCast3D = {
    ok() {
      if (!window.NZA3D || !THREE) return false;
      if (!NZA.inGame && /[?&]no3d=1\b/.test(location.search)) return false;
      try { return !!NZA3D.supported(); } catch (e) { return false; }
    },
    // → the app's mode handle (S.m): key / keyUp / result / destroy (on whichever game runs: a restore
    // that could not be rebuilt swaps in a fresh one)
    start(ctx) {
      const h = { g: null };
      const g = new Game(ctx, h);
      h.g = g;
      Game.current = g;
      if (!NZA.inGame) { const st = new URLSearchParams(location.search).get('stage'); if (st) g.jump(st); }
      return {
        key: e => (h.g ? h.g.key(e) : false),
        keyUp: () => false,
        result: r => { if (h.g) h.g.showResult(r || {}); },
        destroy: () => { if (h.g) h.g.dispose(); },
        get _game() { return h.g; },
      };
    },
    get debug() {
      return {
        g: Game.current, screen: w => Game.current && Game.current.screen(w), state: () => Game.current && Game.current.debugState(),
        K: { A0, AFAR, PASS, CELLS, WORK_TIME, CMS_END, STEPS: STEPS.slice() },
      };
    },
  };
})();
