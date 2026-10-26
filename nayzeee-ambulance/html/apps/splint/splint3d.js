/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · splint app · 3D CLOSE-UP                          window.Splint3D
   The splint app's 'proc' mode as a full-screen 3D close-up of the broken limb segment on
   core/nza3d.js (the suture / burn look) under the shared procedure HUD (NZA.ui.ProcPanel) and
   the app's own fracture card + splint record. apps/splint/app.js starts it from procStart()
   when WebGL2 works (Splint3D.ok()); otherwise its 2D game over the game camera runs unchanged.

   The limb   the engine's skin patch (region / tone / sex / seed from the data) shaped into the
              segment: joint above (knee, elbow, hip, shoulder) and below (ankle, wrist, knee,
              elbow); the rest of the limb past the patch (lower leg / forearm, foot / hand,
              toes / fingers, nails) is lofted here and drawn with the same skin material. The
              fracture shows: swelling and bruising; a step where it is displaced, with the foot /
              hand turned out; a wound with bone in it (or the dressing on it) when it is open.
   Steps (procedure HUD, 5):
     1 Lay     drag the splint from beside the limb under it (it slips in under the limb), then slide
               it along onto the outline: both ends past the joints. Hold still to set it
               (tune.lockHold) or {set}; {reset} starts over, ← → nudge (Shift fine).
     2 Pad     click the marked bony point at each joint: padding goes in on both sides of it.
     3 Shape   hold LMB on each marked point on the wall: a gloved hand presses the walls in round
               the limb. Let go while the ring is teal (tune.shapeZone); past it = pressure point.
               Shift = gentle.
     4 Strap   hold LMB on a strap: it wraps over the limb, then pulls tight while held; let go on
               the teal arc (tune.strapZone). Past tune.strapTight it cuts the circulation off.
     5 Check   hold LMB on a toe / finger nail until it blanches, let go: the colour comes back in
               the refill time (slow behind a tight strap), the toes / fingers move, the patient
               says what they feel. A tight strap sends you back to step 4 to loosen it.
   Timing     every hold (shape press, strap pull, nail blanch) and the refill check run on the engine's
              simulation clock (simMs: at most 0.2 s per drawn frame), so a hitch never carries a press
              past what the screen showed; the shaping press slows through the teal band (SHAPE_ZONE_S).
              The result's `time` is real seconds (the server's minTime / maxTime see the real session).
   Step away  P / "Step away" on the procedure HUD (core ProcPanel opts.pause, shown once the scene is up,
              off on the record): snapshot() goes to Lua ('_proc:pause'), the server parks the session for
              Config.ProcPause.keep and the app closes. Using the same option on the same fracture again
              opens it with data.resume = that snapshot and boot() → restore() rebuilds the same point on a
              fresh scene: the splint where it lay (beside / under the limb, its offset, set or not), the pads
              in, every shaping point's press (set, pressed too far, let go short), every strap open /
              wrapped / locked at its tension (a tight one still red after a failed check), the checks done,
              resets, scores and the clock. Positions are kept as offsets / indices, so a slightly different
              limb length still fits. null while a move is half done (dragging the splint, pressing a wall
              point, pulling a strap, pressing a nail, the refill check running): the HUD says to finish it.
              Every field is checked: an unreadable one starts its own step over, a step is entered only when
              the ones before it are done, content of a step later than the one it was on is never taken;
              a snapshot for another fracture / limb (injury, region, scene seed) or an unreadable one (not
              even where the splint lay can be read) starts fresh with a note; one that throws while
              rebuilding restarts the game cleanly.
              Supplies: the game counts none (the splint item is checked when it opens and taken on success;
              padding and straps come with it), so nothing here can run out part-way.
   Lua → JS   the app's open data (see app.js) + tone / seed (server/modules/splint.lua; without them
              the skin is picked from a hash of the patient name, like the other close-ups) + resume?
              (client/modules/splint.lua copies ctx.data into the open payload)
   JS → Lua   exactly the 2D posts: splint:finish { score, align, mould, straps, cms, checks, pressure,
              padded, tight, loose, resets, time } · splint:abort {} · splint:done {} (app.showResult)
              · '_proc:pause' { snapshot } (core, Step away)
   Preview    index.html?app=splint&mode=proc&stage=place|aligned|pad|shape|strap|tension|cmsready|cms|
              cmsbad|done  (arm-<stage> = forearm)  &region=r_upper_leg|l_lower_arm|…  &tone=0..1  &sex=m|f
              &open=1 &dressed=1 &displaced=0|1 &no3d=1 (the 2D game)
              index.html?app=splint&resume=lay|pad|shape|strap|loosen|cms: sets that mid-game point, steps
              away and opens again from the snapshot (P in the preview parks it, Reopen carries on).
   Debug      Splint3D.debug() / window.SplintDebug() → the running game's progress (emulator scenarios).
   Everything 3D the engine lacks (limb shape, foot / hand, splint, padding, straps, gloved hands,
   markers) is built here with THREE on S.scene and freed with the scene (S.dispose + this bin).
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  if (!window.NZA) return;
  const THREE = window.THREE;
  const APP = 'splint';
  const MM = 0.001, TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const gauss = (x, w) => Math.exp(-(x / w) * (x / w));
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const keyLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC', ShiftLeft: 'Shift' })[c] || String(c || '').replace(/^Key|^Digit/, '');
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };
  const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
  const mmOf = m => Math.round(Math.abs(m) * 1000);

  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, v); }); return s; };

  // the 2D game's tuning (Config.Splint.Splint via data.tune) and keys
  const DEF_TUNE = {
    tolerance: 0.035, lockHold: 0.7, nudgeSpeed: 0.2, fine: 0.22, shapePoints: { leg: 6, arm: 5 }, shapeSeconds: 1.15, shapeClick: 0.18,
    shapeZone: [0.72, 1.0], strapZone: [0.55, 0.82], strapTight: 0.88, strapPeriod: 1.7,
  };
  const DEF_KEYS = { rotateLeft: 'KeyQ', rotateRight: 'KeyE', reset: 'KeyX', set: 'Space' };
  const SIZE = { leg: { width: 0.15, depth: 0.07, wall: 0.01 }, arm: { width: 0.105, depth: 0.05, wall: 0.008 } };
  // how far the splint reaches past each joint (m): immobilise the joint above and below
  const EXT = { leg: { lower: [0.085, 0.075], upper: [0.05, 0.13] }, arm: { lower: [0.05, 0.07], upper: [0.04, 0.08] } };
  const STRAP_W = { leg: 0.042, arm: 0.034 };
  const SEG = { lower_leg: [0.42, 0.34, 0.5], upper_leg: [0.44, 0.36, 0.52], lower_arm: [0.26, 0.21, 0.32], upper_arm: [0.29, 0.23, 0.35] };
  const RAD = { lower_leg: 0.055, upper_leg: 0.075, lower_arm: 0.04, upper_arm: 0.05 };   // = the engine's region presets
  const TONES = [0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88];
  const BLANCH = 0.7;           // s of pressing a nail until it is white
  const WRAP_T = 0.45;          // s for a strap to go round the limb
  const SHAPE_ZONE_S = 0.8;     // s at least that a shaping press stays in the teal band
  // step away / carry on (see the header)
  const num = (v, fb) => { const n = Number(v); return v !== null && v !== '' && typeof v !== 'boolean' && Number.isFinite(n) ? n : fb; };
  const rnd = (v, k) => { const m = Math.pow(10, k); return Math.round(v * m) / m; };
  const bit = v => (v === 1 || v === true ? 1 : v === 0 || v === false ? 0 : -1);
  const intIn = (v, lo, hi) => { const n = num(v, NaN); return Number.isInteger(n) && n >= lo && n <= hi ? n : null; };
  const numIn = (v, lo, hi) => { const n = num(v, NaN); return n >= lo && n <= hi ? n : null; };
  const plain = v => !!v && typeof v === 'object' && !Array.isArray(v);
  const MAX_SNAP_T = 3600;
  let PARKED = null;            // preview: the snapshot "Step away" kept (Reopen carries on from it)
  let PREVIEW_MOCKED = false;   // preview: the '_proc:pause' mock is installed once per page (a test may replace it)
  let PREVIEW_PARKED = false;   // preview: ?resume=<stage> runs once per page
  let NEXT_NOTE = null;         // the note the next game opens with (a snapshot that could not be rebuilt)
  let CURRENT = null;           // the running game (Splint3D.debug)

  // limb radius scale r (of the engine's R) and vertical squash e along the segment
  // (q = 0 at the proximal joint, 1 at the distal one); the bottom of the limb stays on the blanket
  const PROFILE = {
    lower_leg: q => [1 + 0.3 * smooth(-0.04, -0.45, q) + 0.06 * gauss(q + 0.01, 0.07) + 0.035 * gauss(q - 0.25, 0.2) - 0.13 * smooth(0.5, 0.95, q), 1 - 0.06 * smooth(0.75, 1, q)],
    upper_leg: q => [1 + 0.05 * smooth(0.15, -0.25, q) - 0.12 * smooth(0.3, 0.92, q) + 0.04 * gauss(q - 1, 0.08) - 0.17 * smooth(1.06, 1.32, q), 1],
    lower_arm: q => [1 + 0.2 * smooth(-0.04, -0.45, q) + 0.05 * gauss(q, 0.08) + 0.06 * gauss(q - 0.22, 0.18) - 0.17 * smooth(0.45, 0.97, q), 1 - 0.2 * smooth(0.45, 0.97, q)],
    upper_arm: q => [1 + 0.06 * gauss(q - 0.45, 0.28) - 0.08 * smooth(0.6, 0.95, q) + 0.04 * gauss(q - 1, 0.08) - 0.14 * smooth(1.06, 1.3, q), 1 - 0.06 * smooth(1.06, 1.3, q)],
  };

  /* ═════════════════════════════ CSS (stage, cursor ring, loading veil) ═════════════════════════════ */
  const CSS = `
#app-splint .sg3-stage{position:absolute;inset:0;overflow:hidden;cursor:crosshair;pointer-events:auto;background:#050607}
#app-splint .sg3-stage.grab{cursor:grab}
#app-splint .sg3-stage.grabbing{cursor:grabbing}
#app-splint .sg3-stage.hide{cursor:none}
#app-splint .sg3-stage.point{cursor:pointer}
#app-splint .sg3-cur{position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;opacity:0;transition:opacity 140ms}
#app-splint .sg3-cur.on{opacity:1}
#app-splint .sg3-cur svg{position:absolute;left:-23px;top:-23px;width:46px;height:46px;transform:rotate(-90deg)}
#app-splint .sg3-cur.noring svg{display:none}
#app-splint .sg3-cur .bg{stroke:rgba(255,255,255,.22);fill:none;stroke-width:3}
#app-splint .sg3-cur .zn{stroke:rgba(15,212,196,.42);fill:none;stroke-width:6}
#app-splint .sg3-cur .fg{stroke:var(--teal-hi);fill:none;stroke-width:3;stroke-linecap:round;filter:drop-shadow(0 0 4px rgba(15,212,196,.7))}
#app-splint .sg3-cur.red .fg{stroke:#ff7478;filter:drop-shadow(0 0 4px rgba(229,72,77,.7))}
#app-splint .sg3-cur.amber .fg{stroke:#f3c35a;filter:drop-shadow(0 0 4px rgba(229,165,10,.6))}
#app-splint .sg3-cur.white .fg{stroke:#ffffff;filter:drop-shadow(0 0 3px rgba(255,255,255,.5))}
#app-splint .sg3-cur .tx{position:absolute;left:30px;top:-11px;height:22px;display:inline-flex;align-items:center;padding:0 8px;border-radius:6px;white-space:nowrap;
  font:600 11px var(--font);color:var(--white);background:rgba(12,13,16,.86);border:1px solid var(--hud-line)}
#app-splint .sg3-cur.noring .tx{left:16px}
#app-splint .sg3-cur .tx:empty{display:none}
#app-splint .sg3-cur.teal .tx{color:var(--teal-hi)} #app-splint .sg3-cur.red .tx{color:#ff9a9d} #app-splint .sg3-cur.amber .tx{color:#f3c35a}
#app-splint .sg3-load{position:absolute;inset:0;display:grid;place-items:center;background:#050607;transition:opacity 260ms;pointer-events:none}
#app-splint .sg3-load.out{opacity:0}
#app-splint .sg3-load .in{display:flex;flex-direction:column;align-items:center;gap:12px;color:var(--ink-3);font-size:12px}
#app-splint .sg3-load .ring{width:34px;height:34px;border-radius:50%;border:3px solid rgba(255,255,255,.1);border-top-color:var(--teal);animation:sg3-spin 900ms linear infinite}
@keyframes sg3-spin{to{transform:rotate(360deg)}}`;
  function injectCss() {
    if (document.getElementById('sg3-css')) return;
    const s = document.createElement('style');
    s.id = 'sg3-css'; s.textContent = CSS;
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
  // soft cotton padding (cast padding / gauze): a fine weave with fuzz
  function padTex() {
    if (TEX.pad) return TEX.pad;
    const n = 256, h = cvs(n, n), x = h.getContext('2d'), a = cvs(n, n), ax = a.getContext('2d'), r = rng(523);
    x.fillStyle = '#6a6a6a'; x.fillRect(0, 0, n, n);
    ax.fillStyle = '#ece8df'; ax.fillRect(0, 0, n, n);
    const N = 30, step = n / N;
    for (const dir of [0, 1]) {
      for (let k = 0; k < N; k++) {
        const off = (k + 0.5) * step, v = 150 + r() * 70;
        x.strokeStyle = `rgb(${v},${v},${v})`; x.lineWidth = step * 0.5;
        const av = 240 + r() * 12;
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
  // dashed target ring (white; tinted by the sprite)
  function ringTex() {
    if (TEX.ring) return TEX.ring;
    const N = 128, c = cvs(N, N), x = c.getContext('2d'), m = N / 2;
    const g = x.createRadialGradient(m, m, 30, m, m, 62); g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.6, 'rgba(255,255,255,.22)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    x.fillStyle = g; x.fillRect(0, 0, N, N);
    x.strokeStyle = '#fff'; x.lineCap = 'round'; x.lineWidth = 6;
    for (let i = 0; i < 14; i++) { x.beginPath(); x.arc(m, m, 46, (i / 14) * TAU, (i / 14 + 0.045) * TAU); x.stroke(); }
    x.fillStyle = '#fff'; x.beginPath(); x.arc(m, m, 6, 0, TAU); x.fill();
    TEX.ring = c;
    return c;
  }
  // a done mark: filled disc + check (white; tinted by the sprite)
  function checkTex() {
    if (TEX.check) return TEX.check;
    const N = 128, c = cvs(N, N), x = c.getContext('2d'), m = N / 2;
    x.fillStyle = 'rgba(255,255,255,.95)'; x.beginPath(); x.arc(m, m, 34, 0, TAU); x.fill();
    x.globalCompositeOperation = 'destination-out';
    x.strokeStyle = '#000'; x.lineWidth = 10; x.lineCap = 'round'; x.lineJoin = 'round';
    x.beginPath(); x.moveTo(m - 15, m + 1); x.lineTo(m - 4, m + 12); x.lineTo(m + 17, m - 11); x.stroke();
    TEX.check = c;
    return c;
  }
  // the printed foam liner of the channel: u across the channel (rim → floor → far rim), v along it from the
  // proximal end. Closed-cell dimples, a centimetre rule and the device print on the far wall (the one you
  // see), the joint lines across, a warning sticker. Generic device labelling only.
  function linerTex(o) {
    const W = 512, H = 2048, r = rng(o.kind === 'leg' ? 191 : 233);
    const c = cvs(W, H), x = c.getContext('2d');
    const h = cvs(W, H), hx = h.getContext('2d');
    x.fillStyle = '#39424a'; x.fillRect(0, 0, W, H);
    hx.fillStyle = '#8c8c8c'; hx.fillRect(0, 0, W, H);
    for (let i = 0; i < 30; i++) {
      const gx = r() * W, gy = r() * H, gr = 40 + r() * 120, dark = r() > 0.5;
      const g = x.createRadialGradient(gx, gy, 0, gx, gy, gr);
      g.addColorStop(0, dark ? `rgba(10,14,18,${0.03 + r() * 0.04})` : `rgba(160,175,185,${0.02 + r() * 0.025})`); g.addColorStop(1, 'rgba(0,0,0,0)');
      x.fillStyle = g; x.fillRect(gx - gr, gy - gr, gr * 2, gr * 2);
    }
    for (let i = 0; i < 24000; i++) {
      const px = r() * W, py = r() * H, rad = 0.6 + r() * 1.8;
      hx.fillStyle = `rgba(28,28,28,${0.2 + r() * 0.4})`; hx.beginPath(); hx.arc(px, py, rad, 0, 6.2832); hx.fill();
      if (r() < 0.2) { x.fillStyle = `rgba(0,0,0,${0.05 + r() * 0.06})`; x.fillRect(px - rad * 0.5, py - rad * 0.5, rad, rad); }
    }
    const L = o.L, P = o.perim, ku = W / P, kv = H / L;
    const mmAt = (um, vm, rot) => { const cs = Math.cos(rot), sn = Math.sin(rot), k = 0.001; x.setTransform(ku * k * cs, kv * k * sn, -ku * k * sn, kv * k * cs, um * ku, vm * kv); };
    const ink = 'rgba(214,224,228,.82)', inkDim = 'rgba(214,224,228,.5)';
    const font = (mm, w = 600) => `${w} ${mm}px "JetBrains Mono", monospace`;
    // centimetre rule along the far wall (zero at the proximal end)
    const uR = P * 0.86;
    for (let cm = 0; cm <= Math.floor(L * 100); cm++) {
      const vm = cm / 100, long = cm % 5 === 0;
      mmAt(uR, vm, 0);
      x.fillStyle = long ? ink : inkDim;
      x.fillRect(-(long ? 9 : 5.5), -0.35, long ? 9 : 5.5, 0.7);
      for (let mk = 1; mk < 10 && cm < Math.floor(L * 100); mk++) { if (mk !== 5) x.fillRect(-2.2, mk - 0.18, 2.2, 0.36); else x.fillRect(-3.6, mk - 0.22, 3.6, 0.44); }
      if (long && cm > 0) {
        mmAt(uR + 0.0062, vm, Math.PI / 2);
        x.fillStyle = ink; x.font = font(5.6, 700); x.textAlign = 'center'; x.textBaseline = 'middle';
        x.fillText(String(cm), 0, 0);
      }
    }
    mmAt(uR - 0.0005, 0, 0); x.fillStyle = inkDim; x.fillRect(-0.3, 0, 0.6, L * 1000);
    // joint lines across the whole liner (line the joints up with them)
    (o.sites || []).forEach((s, i) => {
      const vm = s.x + L / 2;
      mmAt(0, vm, 0);
      x.fillStyle = 'rgba(47,224,208,.85)';
      for (let u = 6; u < P * 1000 - 6; u += 5) x.fillRect(u, -0.45, 3, 0.9);
      mmAt(P * 0.74, vm + (i === 0 ? -0.006 : 0.006), Math.PI / 2);
      x.fillStyle = 'rgba(47,224,208,.95)'; x.font = font(5.4, 800); x.textAlign = i === 0 ? 'right' : 'left'; x.textBaseline = 'middle';
      x.fillText(`${i === 0 ? '▲ ' : ''}${(i === 0 ? o.print.prox : o.print.dist).toUpperCase()}${i === 0 ? '' : ' ▼'}`, 0, 0);
    });
    // device print along the far wall, repeated
    const line = `${o.print.model} · ${o.print.name.toUpperCase()} · ${o.print.use.toUpperCase()}`;
    x.font = font(4.2, 600); x.textAlign = 'left'; x.textBaseline = 'middle';
    const tw = x.measureText(line).width + 60;
    for (let vmm = 40; vmm < L * 1000 - 60; vmm += tw) { mmAt(P * 0.66, vmm / 1000, Math.PI / 2); x.fillStyle = inkDim; x.fillText(line, 0, 0); }
    // warning sticker on the far wall near the proximal end
    mmAt(P * 0.79, Math.max(0.05, (o.sites && o.sites[0] ? o.sites[0].x + L / 2 : L * 0.2) + 0.05), Math.PI / 2);
    x.scale(1.45, 1.45);
    x.font = font(2.8, 800); const sw1 = x.measureText(o.print.warn.toUpperCase()).width;
    x.font = font(2.1, 600); const sw2 = x.measureText(o.print.warn2.toUpperCase()).width;
    const sw = Math.max(sw1, sw2) + 13.5;
    x.fillStyle = 'rgba(0,0,0,.35)'; x.fillRect(-0.6, -4.6, sw, 10.4);
    x.fillStyle = '#e8a90f'; x.beginPath(); if (x.roundRect) x.roundRect(-1, -5.2, sw, 10.4, 1.2); else x.rect(-1, -5.2, sw, 10.4); x.fill();
    x.fillStyle = '#16181a';
    x.beginPath(); x.moveTo(4.5, -3.6); x.lineTo(8.4, 3.2); x.lineTo(0.6, 3.2); x.closePath(); x.fill();
    x.fillStyle = '#e8a90f'; x.fillRect(4.1, -1.4, 0.8, 2.6); x.fillRect(4.1, 1.8, 0.8, 0.7);
    x.fillStyle = '#16181a'; x.font = font(2.8, 800); x.textAlign = 'left';
    x.fillText(o.print.warn.toUpperCase(), 10.5, -1.3);
    x.font = font(2.1, 600); x.fillText(o.print.warn2.toUpperCase(), 10.5, 2.5);
    x.setTransform(1, 0, 0, 1, 0, 0);
    return { albedo: c, normal: heightToNormal(h, 2.2) };
  }
  // nylon webbing: ribs along the strap, bound edges, teal stitch lines, hook-and-loop patch at the free end
  function webbingTex() {
    if (TEX.web) return TEX.web;
    const w = 64, h = 1024, r = rng(17);
    const c = cvs(w, h), cc = c.getContext('2d');
    cc.fillStyle = '#23272b'; cc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { cc.fillStyle = x % 4 ? 'rgba(255,255,255,.045)' : 'rgba(0,0,0,.25)'; cc.fillRect(x, 0, 1, h); }
    for (let y = 0; y < h; y += 3) { cc.fillStyle = 'rgba(255,255,255,.025)'; cc.fillRect(0, y, w, 1); }
    cc.fillStyle = '#15181a'; cc.fillRect(0, 0, 4, h); cc.fillRect(w - 4, 0, 4, h);
    cc.fillStyle = 'rgba(15,180,168,.85)';
    for (let y = 0; y < h; y += 8) { cc.fillRect(6, y, 2, 5); cc.fillRect(w - 8, y, 2, 5); }
    const p0 = Math.round(h * 0.8);
    cc.fillStyle = '#3a3e42'; cc.fillRect(5, p0, w - 10, h - p0 - 6);
    for (let i = 0; i < 2600; i++) { const l = 50 + r() * 50; cc.fillStyle = `rgba(${l},${l + 3},${l + 6},.8)`; cc.fillRect(5 + r() * (w - 10), p0 + r() * (h - p0 - 6), 1, 1 + r() * 2); }
    cc.strokeStyle = 'rgba(15,180,168,.8)'; cc.lineWidth = 1.2; cc.setLineDash([3, 2]);
    cc.strokeRect(8, p0 + 3, w - 16, h - p0 - 12);
    const hh = cvs(w, h), hc = hh.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { hc.fillStyle = x % 4 ? '#a0a0a0' : '#606060'; hc.fillRect(x, 0, 1, h); }
    hc.fillStyle = '#b8b8b8'; hc.fillRect(0, 0, 3, h); hc.fillRect(w - 3, 0, 3, h);
    for (let i = 0; i < 3000; i++) { hc.fillStyle = r() > 0.5 ? '#c4c4c4' : '#5a5a5a'; hc.fillRect(5 + r() * (w - 10), p0 + r() * (h - p0 - 6), 1, 1); }
    TEX.web = { albedo: c, normal: heightToNormal(hh, 3) };
    return TEX.web;
  }
  // woven edge binding round the rims: fine weave, a stitch line down the middle
  function bindingTex() {
    if (TEX.bind) return TEX.bind;
    const w = 64, h = 256;
    const c = cvs(w, h), x = c.getContext('2d');
    x.fillStyle = '#0a6a62'; x.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 2) { x.fillStyle = y % 4 ? 'rgba(255,255,255,.05)' : 'rgba(0,0,0,.18)'; x.fillRect(0, y, w, 1); }
    const sh = x.createLinearGradient(0, 0, w, 0); sh.addColorStop(0, 'rgba(0,0,0,.35)'); sh.addColorStop(0.2, 'rgba(0,0,0,0)'); sh.addColorStop(0.8, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.35)');
    x.fillStyle = sh; x.fillRect(0, 0, w, h);
    x.fillStyle = 'rgba(205,245,240,.9)';
    for (let y = 2; y < h; y += 12) x.fillRect(w / 2 - 1.5, y, 3, 7);
    const hh = cvs(w, h), hx = hh.getContext('2d');
    hx.fillStyle = '#808080'; hx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 2) { hx.fillStyle = y % 4 ? '#9a9a9a' : '#666'; hx.fillRect(0, y, w, 1); }
    hx.fillStyle = '#5a5a5a'; for (let y = 2; y < h; y += 12) hx.fillRect(w / 2 - 2, y - 1, 4, 9);
    hx.fillStyle = '#c0c0c0'; for (let y = 2; y < h; y += 12) hx.fillRect(w / 2 - 1, y, 2, 7);
    TEX.bind = { albedo: c, normal: heightToNormal(hh, 2.6) };
    return TEX.bind;
  }
  // moulded shell grain
  function shellTex() {
    if (TEX.shell) return TEX.shell;
    const n = 256, r = rng(7);
    const h = cvs(n, n), hc = h.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, n, n);
    for (let i = 0; i < 5000; i++) { hc.fillStyle = `rgba(${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},.06)`; hc.fillRect(r() * n, r() * n, 1 + r() * 2, 1); }
    TEX.shell = heightToNormal(h, 0.6);
    return TEX.shell;
  }
  // closed-cell foam (foot plate pad, palm roll)
  function foamTex() {
    if (TEX.foam) return TEX.foam;
    const n = 256, r = rng(91);
    const h = cvs(n, n), hc = h.getContext('2d');
    hc.fillStyle = '#909090'; hc.fillRect(0, 0, n, n);
    for (let i = 0; i < 1600; i++) {
      const x = r() * n, y = r() * n, rad = 0.8 + r() * 2.6;
      const g = hc.createRadialGradient(x, y, 0, x, y, rad);
      g.addColorStop(0, `rgba(30,30,30,${0.35 + r() * 0.4})`); g.addColorStop(1, 'rgba(30,30,30,0)');
      hc.fillStyle = g; hc.beginPath(); hc.arc(x, y, rad, 0, TAU); hc.fill();
    }
    TEX.foam = heightToNormal(h, 2.4);
    return TEX.foam;
  }
  // the numbered pull tab at the free end of each strap
  function tabTex(n) {
    const k = `tab${n}`;
    if (TEX[k]) return TEX[k];
    const c = cvs(64, 32), x = c.getContext('2d');
    x.fillStyle = '#0b8379'; x.fillRect(0, 0, 64, 32);
    x.fillStyle = 'rgba(255,255,255,.12)'; x.fillRect(0, 0, 64, 3);
    x.fillStyle = '#e9fffb'; x.font = '800 22px "JetBrains Mono", monospace'; x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillText(String(n), 32, 17);
    TEX[k] = c;
    return c;
  }

  /* ═════════════════════════════ geometry helpers ═════════════════════════════ */
  // sweep a rounded cross-section along a spine: prof(t) → { w, h, e (superellipse), pad } (the gloved hands)
  function sweepGeo(pts, prof, o = {}) {
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
    const NS = o.seg || 32, NR = o.rad || 18, CAP = 6;
    const up0 = (o.up || V3(0, 0, 1)).clone().normalize();
    const rings = [];
    for (let i = 0; i <= NS; i++) rings.push({ t: i / NS, k: 1, adv: 0 });
    if (o.capEnd) for (let j = 1; j <= CAP; j++) { const a = (j / CAP) * Math.PI / 2; rings.push({ t: 1, k: Math.max(0.02, Math.cos(a)), adv: Math.sin(a) }); }
    const P = [], UVs = [], idx = [];
    const Tg = V3(), B = V3(), Sd = V3(), p = V3();
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
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nv * 3), 3));
    const uv = new Float32Array(nv * 2);
    for (let j = 0; j <= rows; j++) for (let i = 0; i <= cols; i++) { const k = j * (cols + 1) + i; uv[k * 2] = i / cols; uv[k * 2 + 1] = 1 - j / rows; }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    const idx = [];
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) { const a = j * (cols + 1) + i, b = a + 1, c = a + cols + 1, d = c + 1; idx.push(a, c, b, b, c, d); }
    g.setIndex(idx);
    return g;
  }
  // skin loft: rings { c, U, Z (unit; T = U × Z is the way the rings advance), hu, hz, eu, ed (superellipse
  // exponents toward +U / −U), ur (metres along the limb past the patch end), rho (radius for v) }.
  // The uv continue the engine's patch past its end (u = 1 + ur / W, v = 0.5 − θ·rho / H, θ = 0 on +U: the
  // patch's own angle), so the skin material shades it like the patch: the micro detail runs on, the colour
  // map mirrors at the seam (its wrap is set to mirrored) and the wound / paint layers stay on the patch.
  function loftGeo(rings, NR, W, H) {
    const n = rings.length, nv = n * (NR + 1);
    const pos = new Float32Array(nv * 3), uv = new Float32Array(nv * 2), idx = [];
    for (let i = 0; i < n; i++) {
      const rg = rings[i];
      for (let j = 0; j <= NR; j++) {
        const th = -Math.PI + TAU * j / NR, c = Math.cos(th), s = Math.sin(th);
        const e = c >= 0 ? (rg.eu || 2) : (rg.ed || 2);
        const cx = Math.sign(c) * Math.pow(Math.abs(c), 2 / e), sz = Math.sign(s) * Math.pow(Math.abs(s), 2 / e);
        const k = i * (NR + 1) + j;
        pos[k * 3] = rg.c.x + rg.U.x * rg.hu * cx + rg.Z.x * rg.hz * sz;
        pos[k * 3 + 1] = rg.c.y + rg.U.y * rg.hu * cx + rg.Z.y * rg.hz * sz;
        pos[k * 3 + 2] = rg.c.z + rg.U.z * rg.hu * cx + rg.Z.z * rg.hz * sz;
        uv[k * 2] = 1 + rg.ur / W; uv[k * 2 + 1] = 0.5 - th * rg.rho / H;
      }
    }
    for (let i = 0; i < n - 1; i++) {
      for (let j = 0; j < NR; j++) {
        const a = i * (NR + 1) + j, b = a + 1, c = a + NR + 1, d = c + 1;
        idx.push(a, b, c, b, d, c);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    return g;
  }
  // tube rings along a spine (parallel-transported frame from up0): prof(t) → { hu, hz, eu, ed }; cap closes the end
  function tubeRings(pts, n, prof, up0, ur0, cap) {
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
    const len = curve.getLength(), out = [];
    let U = up0.clone().normalize();
    for (let i = 0; i <= n; i++) {
      const t = i / n, c = curve.getPointAt(t), Tg = curve.getTangentAt(t).normalize();
      U.addScaledVector(Tg, -U.dot(Tg)).normalize();
      const Z = V3().crossVectors(Tg, U).normalize();
      const p = prof(t);
      out.push({ c, U: U.clone(), Z, hu: p.hu, hz: p.hz, eu: p.eu || 2, ed: p.ed || 2, ur: ur0 + t * len, rho: Math.sqrt(p.hu * p.hz), T: Tg.clone() });
    }
    if (cap) {
      const last = out[out.length - 1], r0 = Math.min(last.hu, last.hz);
      for (let j = 1; j <= 5; j++) {
        const a = (j / 5) * Math.PI / 2, k = Math.max(0.03, Math.cos(a));
        out.push(Object.assign({}, last, { c: last.c.clone().addScaledVector(last.T, r0 * Math.sin(a) * 0.95), hu: last.hu * k, hz: last.hz * k, ur: last.ur + r0 * Math.sin(a), rho: last.rho * k }));
      }
    }
    return out;
  }
  // the upper convex hull of points [z, y] ordered from +z to −z (a strap pulled over the limb)
  function upperHull(pts) {
    const P = pts.map(p => [-p[0], p[1]]).sort((a, b) => a[0] - b[0]), h = [];
    for (const p of P) {
      while (h.length >= 2) {
        const o = h[h.length - 2], a = h[h.length - 1];
        if ((a[0] - o[0]) * (p[1] - o[1]) - (a[1] - o[1]) * (p[0] - o[0]) >= 0) h.pop(); else break;
      }
      h.push(p);
    }
    return h.map(p => [-p[0], p[1]]);
  }
  // resample a polyline [[z, y]…] to n points evenly along its length
  function resample(path, n) {
    const L = [0];
    for (let i = 1; i < path.length; i++) L.push(L[i - 1] + Math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]));
    const tot = L[L.length - 1] || 1e-6, out = [];
    let k = 1;
    for (let i = 0; i < n; i++) {
      const d = (i / (n - 1)) * tot;
      while (k < path.length - 1 && L[k] < d) k++;
      const f = clamp((d - L[k - 1]) / Math.max(1e-9, L[k] - L[k - 1]), 0, 1);
      out.push([lerp(path[k - 1][0], path[k][0], f), lerp(path[k - 1][1], path[k][1], f)]);
    }
    out.len = tot;
    return out;
  }

  /* ═════════════════════════════ the medic's gloved hand (as treat/bleed3d.js) ═════════════════════════════
     Tool frame: origin at the contact point, +Y toward the wrist, back of the hand +Z, palm −Z, thumb +X.
     press = the flat of the fingers on a surface, point = the index finger out (presses a nail) */
  const HAND_POSE = {
    press: { flex: [[0.2, 0.22, 0.1], [0.18, 0.22, 0.1], [0.2, 0.24, 0.1], [0.24, 0.26, 0.12]], thumb: [0.35, 0.2, 0.12], thumbDir: [0.42, -0.82, -0.3], wrist: 0.16 },
    point: { flex: [[0.06, 0.05, 0.02], [1.35, 1.5, 0.85], [1.4, 1.55, 0.85], [1.45, 1.55, 0.85]], thumb: [0.95, 0.75, 0.6], thumbDir: [0.5, -0.66, -0.5], wrist: 0.12 },
  };
  function buildHand(M, keep, poseName, noSleeve) {
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
    // wrist, rolled cuff and sleeve on a pivot: the forearm rises off the surface
    const wrist = new THREE.Group();
    wrist.position.set(-0.002, 0.086, 0.001); wrist.rotation.x = P.wrist;
    inner.add(wrist);
    wrist.add(new THREE.Mesh(keep(sweepGeo([V3(0, 0.002, 0), V3(0, 0.034, 0.001), V3(0, 0.082, 0.002)], t => ({ w: lerp(0.035, 0.031, t), h: lerp(0.016, 0.021, t), e: 2.3 }), { seg: 10, rad: 24 })), M.glove));
    const cuff = new THREE.Mesh(keep(new THREE.TorusGeometry(0.033, 0.0034, 10, 36)), M.glove);
    cuff.rotation.x = Math.PI / 2; cuff.scale.set(1, 0.68, 1); cuff.position.set(0, 0.082, 0.002); wrist.add(cuff);
    const knit = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.036, 0.035, 0.03, 32, 1, true)), M.sleeve);
    knit.scale.set(1, 1, 0.72); knit.position.set(0, 0.104, 0.002); wrist.add(knit);
    // the uniform sleeve runs on well past the edge of the screen (no cut-off end in view)
    if (!noSleeve) { const slv = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.056, 0.038, 0.46, 32, 1, true)), M.sleeve); slv.scale.set(1, 1, 0.8); slv.position.set(0, 0.344, 0.005); wrist.add(slv); }
    else { const cap = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.037, 0.036, 0.012, 32, 1, false)), M.sleeve); cap.scale.set(1, 1, 0.72); cap.position.set(0, 0.125, 0.002); wrist.add(cap); }
    inner.updateMatrixWorld(true);
    const c = poseName === 'point' ? pads[0].getWorldPosition(V3()) : [0, 1, 2].reduce((v, i) => v.add(pads[i].getWorldPosition(V3())), V3()).multiplyScalar(1 / 3);
    const SC = 0.86;
    inner.scale.setScalar(SC);
    inner.position.copy(c).multiplyScalar(-SC);
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    g.visible = false;
    return { group: g, inner };
  }

  /* ═════════════════════════════ preview data (browser only) ═════════════════════════════ */
  const PREV = {
    lower_leg: { j: ['Knee', 'Ankle', 'toes', 'knee', 'ankle', 'toes'], bone: ['tibia_fibula', 'Tibia and fibula'], label: 'lower leg', dev: ['Contour leg splint', 'CS-76'] },
    upper_leg: { j: ['Hip', 'Knee', 'toes', 'hip', 'knee', 'toes'], bone: ['femur', 'Femur'], label: 'thigh', dev: ['Contour leg splint', 'CS-76'] },
    lower_arm: { j: ['Elbow', 'Wrist', 'fingers', 'elbow', 'wrist', 'fingers'], bone: ['radius_ulna', 'Radius and ulna'], label: 'forearm', dev: ['Contour arm splint', 'CS-40'] },
    upper_arm: { j: ['Shoulder', 'Elbow', 'fingers', 'shoulder', 'elbow', 'fingers'], bone: ['humerus', 'Humerus'], label: 'upper arm', dev: ['Contour arm splint', 'CS-40'] },
  };
  function previewTweak(d) {
    if (NZA.inGame) return;
    const q = new URLSearchParams(location.search);
    const reg = q.get('region');
    const m = reg && /^([lr])_(upper|lower)_(arm|leg)$/.exec(reg);
    if (m) {
      const k3 = `${m[2]}_${m[3]}`, p = PREV[k3];
      d.region = reg; d.regionLabel = `${m[1] === 'l' ? 'Left' : 'Right'} ${p.label}`;
      d.device = d.limb = m[3]; d.segment = m[2];
      d.joints = { prox: p.j[0], dist: p.j[1], cms: p.j[2], proxKey: p.j[3], distKey: p.j[4], cmsKey: p.j[5] };
      d.fracture = Object.assign({}, d.fracture || {}, { bone: p.bone[0], boneLabel: p.bone[1] });
      d.deviceLabel = p.dev[0]; d.deviceModel = p.dev[1];
      d.size = Object.assign({}, SIZE[m[3]]);
      d.segLen = SEG[k3][0];
    }
    if (q.get('tone') !== null) d.tone = clamp(+q.get('tone') || 0, 0, 1);
    if (q.get('sex')) d.sex = q.get('sex') === 'f' ? 'f' : 'm';
    if (q.get('open') !== null) { d.open = q.get('open') === '1'; d.fracture = Object.assign({}, d.fracture || {}, { kind: d.open ? 'open' : 'closed', kindLabel: d.open ? 'Open fracture' : 'Closed fracture' }); }
    if (q.get('dressed') !== null) d.dressed = q.get('dressed') === '1';
    if (q.get('displaced') !== null) d.fracture = Object.assign({}, d.fracture || {}, { displaced: q.get('displaced') === '1', angle: q.get('displaced') === '1' ? (d.fracture && d.fracture.angle) || 14 : 0 });
    if (q.get('pulse')) d.pulse = q.get('pulse');
    // "Step away" in the browser: keep the snapshot and close; Reopen carries on from it (in game: using
    // the same option again within Config.ProcPause.keep). A test may replace this mock after the first open.
    if (!PREVIEW_MOCKED) {
      PREVIEW_MOCKED = true;
      NZA.mock('_proc:pause', r => { PARKED = r && r.snapshot; setTimeout(() => NZA.close(APP), 80); return { ok: true }; });
    }
    if (PARKED && d.resume === undefined) { d.resume = PARKED; PARKED = null; }
  }

  /* ═════════════════════════════ THE GAME ═════════════════════════════ */
  class Game {
    constructor(app, data) {
      this.app = app; this.d = data;
      LOC = Object.assign({}, data.locale || {});
      previewTweak(data);
      const d = data;
      const region = String(d.region || '');
      this.kind = d.device === 'arm' || d.limb === 'arm' || (!d.device && /arm/.test(region)) ? 'arm' : 'leg';
      this.segment = d.segment === 'upper' || d.segment === 'lower' ? d.segment : (/upper/.test(region) ? 'upper' : 'lower');
      this.upper = this.segment === 'upper';
      this.key3 = `${this.segment}_${this.kind}`;
      this.side = /^l_/.test(region) ? -1 : 1;
      const tune = Object.assign({}, DEF_TUNE);
      Object.entries(d.tune || {}).forEach(([k, v]) => { if (v !== null && v !== undefined) tune[k] = v; });
      this.tune = tune;
      this.K = Object.assign({}, DEF_KEYS, d.keys || {});
      this.size = Object.assign({}, SIZE[this.kind]);
      Object.entries(d.size || {}).forEach(([k, v]) => { if (+v > 0) this.size[k] = +v; });
      const ext = EXT[this.kind][this.segment];
      this.extP = ext[0]; this.extD = ext[1];
      const sd = SEG[this.key3];
      this.seg = clamp(+d.segLen || sd[0], sd[1], sd[2]);
      this.Ls = this.seg + this.extP + this.extD;
      // the app's own cards read these (fracture card, splint record)
      Object.assign(app, { d, tune, K: this.K, kind: this.kind, segment: this.segment, size: this.size, extP: this.extP, extD: this.extD, segLen: this.seg, Ls: this.Ls });

      // splint-local layout (x along the splint, 0 = its middle): joints, shaping points, straps (as the 2D game)
      const L = this.Ls, xJp = -L / 2 + this.extP, xJd = L / 2 - this.extD;
      const fr = d.fracture || {};
      const frac = clamp(+fr.at || (0.4 + (hash(`${d.name || ''}:${region}`) % 1000) / 1000 * 0.22), 0.3, 0.7);
      const xFr = xJp + (xJd - xJp) * frac;
      const sp = tune.shapePoints;
      const nPts = clamp(Math.round(Number(typeof sp === 'object' && sp ? sp[this.kind] : sp) || (this.kind === 'leg' ? 6 : 5)), 3, 9);
      const pts = [];
      for (let i = 0; i < nPts; i++) {
        const x = (xJp - this.extP * 0.45) + ((xJd + this.extD * 0.3) - (xJp - this.extP * 0.45)) * (i / (nPts - 1));
        pts.push({ x, f: 0, done: false, tight: false, pop: 0 });
      }
      // (the first strap sits a little further up than the 2D game's, off the knee cap / elbow point)
      const sA = xJp - this.extP * 0.6, sC = xJd - 0.015, room1 = xFr - xJp, room2 = xJd - xFr;
      const sB = room1 > room2 ? xFr - Math.min(0.11, room1 * 0.55) : xFr + Math.min(0.11, room2 * 0.55);
      // the state object doubles as the app's S (app.showResult / splintMapSVG / renderFracture read it)
      this.st = app.S = {
        step: 1, active: true, t0: performance.now(), finished: false, result: null, frac, xFr,
        sites: [{ key: 'prox', x: xJp, padded: false, pop: 0 }, { key: 'dist', x: xJd, padded: false, pop: 0 }],
        points: pts,
        straps: [sA, sB, sC].map((x, i) => ({ i, x, state: 'open', k: 0, tension: 0, quality: 0, locks: 0, tight: false, loose: false })),
        cms: { state: 'hidden', checks: 0, fixed: false, rows: null, tight: false, refill: 0, shown: 0 },
        tightEver: 0, s1: 0, s2: 0, s3: 0, resets: 0, shapeDone: false,
      };
      // carrying on after "Step away": data.resume (checked and rebuilt in boot → restore)
      this.hasResume = d.resume !== undefined && d.resume !== null;
      this.resumed = false; this.note = NEXT_NOTE; NEXT_NOTE = null;
      // one function for the panel's "Step away" (a stable reference: pp.set only re-arms on change)
      this.pauseFn = () => this.snapshot();
      CURRENT = this;
      this.alive = true; this.ready = false; this.step = 0; this.t = 0; this.lmb = false; this.shift = false; this.uiAt = 0;
      this.held = new Set();
      this.cur = { p: null, text: '', tone: '', zone: null };
      this.bin = new Set();
      this.camOff = V3(); this.camOffT = V3();

      // the app shell: an opaque full-screen close-up, no game-camera input
      app.full = true; app.opaque = true; app.camInput = false;
      app.el.classList.add('nza-full');
      injectCss();
      this.stage = el('div', 'sg3-stage');
      app.el.insertBefore(this.stage, app.el.firstChild);
      this.loadEl = el('div', 'sg3-load', `<div class="in"><span class="ring"></span><span>${NZA.esc(T('g3_loading', 'Preparing the close-up…'))}</span></div>`);
      app.el.insertBefore(this.loadEl, this.stage.nextSibling);
      this.curEl = el('div', 'sg3-cur', '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="zn" cx="23" cy="23" r="19" stroke-dasharray="0 120"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>');
      app.el.appendChild(this.curEl);
      this.curFg = this.curEl.querySelector('.fg'); this.curZn = this.curEl.querySelector('.zn'); this.curTx = this.curEl.querySelector('.tx');

      this.pp = app.pp = NZA.ui.ProcPanel(app.el, {
        step: 1, total: 5, tag: `${T('tag', 'Splinting')} · ${d.regionLabel || ''}`.replace(/ · $/, ''),
        steps: this.stepNames(), title: '', text: '', stats: [], tools: this.toolsFor(), hints: [],
        abort: { label: T('abort', 'Hold to stop'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(), onTool: k => this.pickTool(k),
      });
      try { app.renderFracture(); } catch (e) { console.error('[splint] card', e); }
      const S0 = this.st;
      // the opening warning (open / displaced fracture): at the start of a fresh game; a game that opens
      // with a note (a snapshot that did not fit) shows it after the note; a resumed one showed it before
      const warnText = d.open ? (d.dressed ? T('open_dressed', 'Open fracture, already covered. Keep the dressing clean under the splint.') : T('open_warn', 'Open fracture: the bone broke the skin. Cover it before you strap over it.'))
        : fr.displaced ? T('displaced', 'Displaced %s°. Splint it where it lies - it is set in hospital.', Math.round(fr.angle || 0)) : null;
      this.openWarn = warnText ? () => { if (this.alive && this.st === S0 && this.step <= 1) this.pp.flash('warn', warnText, d.open ? 5200 : 4600); } : null;
      if (this.openWarn && !this.hasResume && !this.note) setTimeout(this.openWarn, 700);

      // keys (the app's key maps: the core routes them to the top app)
      const K = this.K;
      const tool = e => !!(this.pp && !e.repeat && this.pp.key(e));
      app.keys = {
        [K.set || 'Space']: e => { if (!e.repeat) this.keySet(); return true; },
        [K.reset || 'KeyX']: e => { if (!e.repeat) this.keyReset(); return true; },
        ArrowLeft: () => { this.held.add('l'); return true; },
        ArrowRight: () => { this.held.add('r'); return true; },
        Shift: () => { this.setShift(true); return false; },
        1: tool, 2: tool, 3: tool, 4: tool, 5: tool,
        Enter: e => !!(this.pp && this.pp.key(e)),
      };
      app.keysUp = {
        ArrowLeft: () => { this.held.delete('l'); return true; },
        ArrowRight: () => { this.held.delete('r'); return true; },
        Shift: () => { this.setShift(false); return false; },
      };
      this.onBlur = () => { this.held.clear(); this.setShift(false); if (this.lmb) this.up({ button: 0 }); };
      this.onResize = () => { this.zoom = 0; };
      window.addEventListener('blur', this.onBlur);
      window.addEventListener('resize', this.onResize);
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive) this.boot(); }));
    }

    keep(x) { if (x) this.bin.add(x); return x; }
    // the engine's simulation clock (ms): it advances at most 0.2 s per drawn frame, so a hold that is
    // timed on it never jumps past what the screen showed (fair at a low frame rate / hitches)
    simMs() { return this.t * 1000; }

    /* ─────────────── scene ─────────────── */
    boot() {
      const d = this.d;
      const name = d.name || (d.patient && d.patient.name) || '';
      const seed = (+d.seed || hash(`${name}:${d.region || ''}:splint`)) >>> 0;
      this.seed = seed;
      this.R0 = rng(seed);
      const tone = d.tone !== undefined && d.tone !== null && d.tone !== '' ? clamp(+d.tone || 0, 0, 1) : TONES[hash(name || 'patient') % TONES.length];
      const sex = /^f/i.test(String(d.sex || (d.patient && d.patient.sex) || 'm')) ? 'f' : 'm';
      this.sex = sex; this.tone = tone;
      // patch: from well past the proximal joint to just past the distal one (lower segments: the foot /
      // hand is lofted on), or 22 cm past it (upper segments: the lower leg / forearm continues)
      const Rg = RAD[this.key3];
      const MP = this.kind === 'leg' ? 0.48 : 0.38, MD = this.upper ? 0.22 : 0.006;
      const W = MP + this.seg + MD, H = TAU * Rg * 0.995;
      this.W = W; this.H = H;
      this.sP = -W / 2 + MP; this.sD = this.sP + this.seg; this.xEnd = W / 2;
      this.xT = this.sP - this.extP + this.Ls / 2;          // the splint's middle when it is laid right
      const x0w = this.sP - 0.24;                             // the work window (field + paint) covers x0w → the end
      const opts = {
        tone, region: d.region || (this.kind === 'arm' ? 'r_lower_arm' : 'r_lower_leg'), sex, seed, quality: (d.cfg && d.cfg.quality) || 'medium',
        size: [W, H], work: [this.xEnd - x0w, H],
        focus: { uv: [((x0w + this.xEnd) / 2) / W + 0.5, 0.5], size: [this.xEnd - x0w - 0.1, H * 0.7], view: 0.9 },
      };
      let S;
      try { S = NZA3D.createScene(this.stage, opts); } catch (e) { console.error('[splint] 3D scene', e); return this.fail(); }
      this.S = S;
      this.R = S.shape.R; this.yb = -2 * this.R;
      this.prof = PROFILE[this.key3];
      this.clothY = this.yb - 0.0165;
      S.controls.limits.pitchMin = 0.42; S.controls.limits.yaw = 1.0;
      // the blanket under the limb: dark field blanket, flatter folds, low enough for the splint shell
      if (S._cloth) {
        const c = S._cloth;
        c.material.color.setHex(0x2b3a40); c.position.y = this.clothY; c.scale.set(2, 2, 0.12);
        [c.material.map, c.material.normalMap].forEach(t => { if (t) t.repeat.set(140, 140); });
      }
      // the view is wide (a whole limb segment): the lamp shadows need a little more bias
      [S.lights.key, S.lights.keyB].forEach(l => { if (l && l.castShadow) { l.shadow.normalBias = 0.0016; l.shadow.bias = -0.0004; } });
      try {
        this.M = this.materials();
        this.makeJoints();
        this.makeFracture();
        this.shapeSkin();
        this.makeProxy();
        S.skin.macro.wrapS = THREE.MirroredRepeatWrapping; S.skin.macro.needsUpdate = true;
        this.makeDistal();
        this.makeSplint();
        this.makeTools();
      } catch (e) { console.error('[splint] 3D build', e); return this.fail(); }
      this.prewarm();
      S.on('frame', (dt, render) => this.frame(dt, render !== false));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.on('pointer', () => { if (this.ready && !this.st.finished) this.pointer(); });
      S.start();
      this.ready = true;
      // carrying on after "Step away" (data.resume): rebuild the saved point on this fresh scene. A snapshot
      // for another fracture or an unreadable one starts fresh with a note; one that cannot be rebuilt
      // restarts the game cleanly (never a half-rebuilt scene)
      let first = 1, note = this.note;
      if (this.hasResume) {
        const snap = plain(d.resume) ? d.resume : null;
        const m = snap ? this.limbMatch(snap.w) : 'bad';
        if (m === 'same') {
          // (nothing readable, not even where the splint lay: a fresh start, said as such)
          try { first = this.restore(snap); this.resumed = !this.restoreEmpty; if (!this.resumed) note = 'bad'; } catch (e) {
            console.error('[splint] restore', e);
            return this.restartClean();
          }
        } else note = m;
      }
      this.enter(first, true);
      this.pp.set({ pause: this.pauseFn });          // "Step away" (P): park the splint, carry on later
      if (this.resumed) { this.refreshTools(); this.pp.flash('ok', T('g3_resume', 'Carrying on where you left off.'), 3200); }
      else if (note) {
        this.pp.flash('warn', note === 'bad' ? T('g3_resume_bad', 'Could not carry on from where you left off - this splint starts from the beginning.') : T('g3_resume_other', 'You stepped away from a different fracture - this one starts from the beginning.'), 4200);
        if (this.openWarn) setTimeout(this.openWarn, 4400);
      }
      this.noteShown = this.resumed ? 'resumed' : note || null;
      setTimeout(() => this.loadEl && this.loadEl.classList.add('out'), 160);
      setTimeout(() => { if (this.loadEl) this.loadEl.style.display = 'none'; }, 520);
      // (a resumed game opens where it was: no preview jump on top of it)
      if (this.pendingJump && !this.resumed) { const j = this.pendingJump; this.pendingJump = null; this.jump(j); }
      this.pendingJump = null;
      // preview: ?resume=<stage> sets that point, steps away and carries on (once per page)
      const pr = !NZA.inGame && !this.hasResume && !PREVIEW_PARKED ? new URLSearchParams(location.search).get('resume') : null;
      if (pr) { PREVIEW_PARKED = true; setTimeout(() => { if (this.alive) this.previewPark(pr); }, 120); }
    }

    // 3D could not start after all: the 2D game takes the session
    fail() {
      const a = this.app, d = this.d;
      window.Splint3D.broken = true;
      a.g3 = null;
      this.dispose();
      try { a.procStart(d); } catch (e) { console.error('[splint] 2D fallback', e); }
    }

    materials() {
      const keep = x => this.keep(x);
      const tex = (c, srgb, rep, clampEdge) => {
        const t = keep(new THREE.CanvasTexture(c));
        t.wrapS = t.wrapT = clampEdge ? THREE.ClampToEdgeWrapping : THREE.RepeatWrapping;
        t.anisotropy = 8;
        if (srgb) t.encoding = THREE.sRGBEncoding;
        if (rep) t.repeat.set(rep[0], rep[1]);
        return t;
      };
      const lin = hex => new THREE.Color(hex).convertSRGBToLinear();
      const pad = padTex(), web = webbingTex(), bind = bindingTex();
      const M = {
        tex, lin,
        glove: keep(new THREE.MeshPhysicalMaterial({ color: 0x1f35a0, roughness: 0.5, normalMap: tex(gloveTex(), false, [2, 2]), normalScale: new THREE.Vector2(0.32, 0.32), sheen: 0.14, sheenRoughness: 0.55, sheenColor: new THREE.Color(0x4a62c0), clearcoat: 0.22, clearcoatRoughness: 0.42, envMapIntensity: 0.7 })),
        sleeve: keep(new THREE.MeshPhysicalMaterial({ color: 0x1d3a4a, roughness: 0.9, normalMap: tex(twillTex(), false, [3, 3]), normalScale: new THREE.Vector2(0.6, 0.6), sheen: 0.5, sheenColor: new THREE.Color(0x6aa4b4), side: THREE.DoubleSide })),
        pad: keep(new THREE.MeshStandardMaterial({ color: 0xd6d1c6, map: tex(pad.albedo, true, [2, 1]), normalMap: tex(pad.normal, false, [2, 1]), normalScale: new THREE.Vector2(1.2, 1.2), roughness: 1, envMapIntensity: 0.5 })),
        shell: keep(new THREE.MeshPhysicalMaterial({ color: lin('#0b8f84'), normalMap: tex(shellTex(), false, [8, 14]), normalScale: new THREE.Vector2(0.25, 0.25), roughness: 0.42, clearcoat: 0.6, clearcoatRoughness: 0.24, side: THREE.DoubleSide, envMapIntensity: 0.9 })),
        cap: keep(new THREE.MeshStandardMaterial({ color: lin('#0a7f76'), roughness: 0.5, side: THREE.DoubleSide })),
        bind: keep(new THREE.MeshStandardMaterial({ map: tex(bind.albedo, true), normalMap: tex(bind.normal, false), normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.78, side: THREE.DoubleSide, envMapIntensity: 0.6 })),
        foam: null,   // the printed liner: built with the splint (it carries the joint lines)
        plateFoam: keep(new THREE.MeshStandardMaterial({ color: lin('#3c444b'), normalMap: tex(foamTex(), false, [4, 4]), roughness: 0.95 })),
        roll: keep(new THREE.MeshStandardMaterial({ color: lin('#59666c'), normalMap: tex(foamTex(), false, [3, 2]), roughness: 0.92 })),
        strap: keep(new THREE.MeshStandardMaterial({ map: tex(web.albedo, true, [1, 1]), normalMap: tex(web.normal, false, [1, 1]), normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.68, side: THREE.DoubleSide, envMapIntensity: 0.7 })),
        metal: keep(new THREE.MeshStandardMaterial({ color: lin('#a3acb2'), metalness: 0.95, roughness: 0.26, envMapIntensity: 1.35 })),
        tab: keep(new THREE.MeshPhysicalMaterial({ color: lin('#0b8379'), roughness: 0.42, clearcoat: 0.6, clearcoatRoughness: 0.25 })),
        dark: keep(new THREE.MeshStandardMaterial({ color: lin('#16191c'), roughness: 0.55, metalness: 0.2 })),
        bone: keep(new THREE.MeshPhysicalMaterial({ color: 0xd9cfb8, roughness: 0.55, clearcoat: 0.5, clearcoatRoughness: 0.35, vertexColors: true })),
        ghost: keep(new THREE.MeshBasicMaterial({ color: 0x2fe0d0, transparent: true, opacity: 0.16, depthWrite: false, side: THREE.DoubleSide, toneMapped: false })),
      };
      M.web = web;
      return M;
    }

    /* ─────────────── the limb ─────────────── */
    // shape at patch point s: centre height, vertical / sideways half axes (the bottom stays on the blanket)
    limbAt(s, out = {}) {
      const q = (s - this.sP) / this.seg, p = this.prof(q), R = this.R;
      out.ry = R * p[0] * p[1]; out.rz = R * p[0]; out.cy = this.yb + out.ry + this.bowAt(s);
      return out;
    }
    // a displaced break lies angulated: the segment bows up to a rounded apex over the break and rests on
    // the joints at both ends (a gap opens under it - it is splinted where it lies)
    bowAt(s) {
      const b = this.bow;
      if (!b) return 0;
      const u = s < b.s0 ? (b.s0 - s) / b.h1 : (s - b.s0) / b.h2;
      if (u >= 1) return 0;
      const c = 0.12, f = v => 1 + c - Math.sqrt(v * v + c * c), lift = (f(u) - f(1)) / (f(0) - f(1));   // 1 at the apex, 0 at the joint
      return b.A * Math.max(0, lift) * smooth(1, 0.82, u);
    }
    limbP(s, a, P) {
      const L = this.limbAt(s, this._la || (this._la = {}));
      // anatomy on top of the profile (knee cap, condyles, ankle / wrist bones, the swelling over the break):
      // compact soft domes added along the radius (the engine's field bumps would shade as pale blisters)
      let k = 1;
      const B = this.shapeB;
      if (B) for (let i = 0; i < B.length; i++) {
        const b = B[i], ds = (s - b.s) / b.rs;
        if (ds > 1 || ds < -1) continue;
        let da = a - b.a; da = ((da + Math.PI) % TAU + TAU) % TAU - Math.PI;
        const dt = (da * this.R) / b.ra, x2 = ds * ds + dt * dt;
        if (x2 < 1) { const w = 1 - x2; k += (b.h * w * w) / (L.rz || this.R); }
      }
      return P.set(s, L.cy + L.ry * k * Math.cos(a), L.rz * k * Math.sin(a));
    }
    limbN(s, a, N) {
      const A = this._na || (this._na = [V3(), V3(), V3(), V3()]);
      this.limbP(s - 0.002, a, A[0]); this.limbP(s + 0.002, a, A[1]); this.limbP(s, a - 0.01, A[2]); this.limbP(s, a + 0.01, A[3]);
      A[1].sub(A[0]); A[3].sub(A[2]);
      return N.crossVectors(A[3], A[1]).normalize();
    }
    uvAt(s, a) { return this.S.stToUv(s, a * this.R); }
    // a point on the visible skin (shape + wound field) and its normal, lifted off it by `lift`
    surfPt(s, a, lift, P, N) {
      this.limbP(s, a, P); this.limbN(s, a, N);
      const h = Math.abs(s) <= this.W / 2 ? this.S.heightAt(this.uvAt(s, a)) : 0;
      return P.addScaledVector(N, h + lift);
    }
    // the blanket's surface height under world (x, z) (its folds, for straps lying on it)
    clothH(x, z) {
      const c = this.S._cloth;
      if (!c) return this.clothY;
      const p = c.geometry.attributes.position, n = 90;
      const fx = clamp((x / c.scale.x + 1.1) / 2.2 * n, 0, n - 1e-3), fy = clamp((1.1 + z / c.scale.y) / 2.2 * n, 0, n - 1e-3);
      const ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy;
      const h = (i, j) => p.getZ(j * (n + 1) + i);
      const v = lerp(lerp(h(ix, iy), h(ix + 1, iy), tx), lerp(h(ix, iy + 1), h(ix + 1, iy + 1), tx), ty);
      return c.position.y + v * c.scale.z;
    }
    // half width of what lies in the splint at patch point s (the heel past the ankle)
    limbHalfZ(s) {
      if (s > this.xEnd - 0.004) return this.kind === 'leg' && !this.upper ? 0.037 * this.footScale() : this.limbAt(this.xEnd).rz;
      return this.limbAt(s).rz;
    }
    footScale() { return this.sex === 'f' ? 0.92 : 1; }

    // the engine's cylinder patch → the limb segment (vertex positions and normals; the field still displaces it)
    shapeSkin() {
      const S = this.S, g = S.skin.mesh.geometry, pos = g.attributes.position, nor = g.attributes.normal, uv = g.attributes.uv;
      const P = V3(), N = V3(), W = this.W, H = this.H, R = this.R;
      for (let i = 0; i < pos.count; i++) {
        const s = (uv.getX(i) - 0.5) * W, a = ((0.5 - uv.getY(i)) * H) / R;
        this.limbP(s, a, P); this.limbN(s, a, N);
        pos.setXYZ(i, P.x, P.y, P.z); nor.setXYZ(i, N.x, N.y, N.z);
      }
      pos.needsUpdate = true; nor.needsUpdate = true;
      g.computeBoundingSphere();
      g.boundingSphere.radius += 0.06;
    }
    // the engine's skin casts no shadow (its depth pass has no wound field): an invisible copy a little inside it does
    makeProxy() {
      const NS = 70, NR = 24, s0 = -this.W / 2, s1 = this.xEnd;
      const rings = [], P = V3();
      for (let i = 0; i <= NS; i++) {
        const s = lerp(s0, s1, i / NS), L = this.limbAt(s);
        rings.push({ c: V3(s, L.cy, 0), U: V3(0, 1, 0), Z: V3(0, 0, 1), hu: L.ry - 0.0025, hz: L.rz - 0.0025, ur: 0, rho: this.R });
      }
      const g = this.keep(loftGeo(rings, NR, this.W, this.H));
      const m = new THREE.Mesh(g, this.keep(new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false })));
      m.castShadow = true; m.frustumCulled = false;
      this.S.scene.add(m);
      void P;
    }
    // the joints: knee cap and condyles, ankle / wrist / elbow bones (shape bumps: s, a, reach along s, around, height)
    makeJoints() {
      const sd = this.side, sP = this.sP, sD = this.sD, E = this.xEnd, B = this.shapeB = [];
      const add = (s, a, rs, ra, h) => B.push({ s, a, rs, ra, h });
      if (this.key3 === 'lower_leg') {
        add(sP - 0.014, 0, 0.034, 0.03, 0.006); add(sP - 0.006, 0.95, 0.036, 0.03, 0.0035); add(sP - 0.006, -0.95, 0.036, 0.03, 0.0035);
        add(sP + 0.05, 0.04, 0.02, 0.016, 0.0022);
        for (let k = 0; k < 5; k++) add(sP + 0.09 + k * 0.05, 0.18 * sd, 0.045, 0.012, 0.0014);      // the shin's crest
        add(E - 0.016, 1.42 * sd, 0.015, 0.015, 0.0045); add(E - 0.022, -1.42 * sd, 0.015, 0.015, 0.004);
      } else if (this.key3 === 'upper_leg') {
        add(sD - 0.008, 0, 0.036, 0.032, 0.0065); add(sD, 0.85, 0.038, 0.032, 0.0035); add(sD, -0.85, 0.038, 0.032, 0.0035); add(sD + 0.06, 0.04, 0.02, 0.016, 0.0022);
      } else if (this.key3 === 'lower_arm') {
        add(sP + 0.004, 1.35, 0.02, 0.016, 0.0035); add(sP + 0.004, -1.35, 0.02, 0.016, 0.0035);
        add(E - 0.016, 1.15 * sd, 0.013, 0.012, 0.0032);
      } else {
        add(sD, 1.4, 0.02, 0.016, 0.004); add(sD, -1.4, 0.02, 0.016, 0.004);
      }
    }
    // the fracture: swelling, bruising, the step of a displaced break, an open wound (bone or a dressing)
    makeFracture() {
      const S = this.S, d = this.d, fr = d.fracture || {}, R = this.R0, sd = this.side;
      const sev = clamp(Math.round(+d.severity || 2), 1, 4);
      const s0 = this.sFr = this.xT + this.st.xFr;
      const uv = (s, a) => this.uvAt(s, a);
      const B = this.shapeB;
      B.push({ s: s0, a: 0.2, rs: 0.07 + sev * 0.008, ra: 0.045, h: 0.0028 + sev * 0.0011 });
      B.push({ s: s0 + 0.01, a: 1.05, rs: 0.06, ra: 0.035, h: 0.0022 + sev * 0.0007 });
      B.push({ s: s0 - 0.006, a: -0.95, rs: 0.055, ra: 0.03, h: 0.0016 + sev * 0.0005 });
      this.angle = fr.displaced ? clamp(+fr.angle || 12, 4, 30) : 0;
      // (the apex rises enough to read from the working camera: ~15 mm at 14°)
      if (this.angle) this.bow = { s0, h1: Math.max(0.05, s0 - this.sP + 0.01), h2: Math.max(0.05, this.sD - s0 + 0.004), A: Math.min(0.022, 0.0105 * this.angle / 10) };
      if (fr.displaced) {
        // the step: the bone end tents the skin just above the break, a hollow just below it
        const k = clamp(this.angle / 18, 0.4, 1.3);
        B.push({ s: s0 - 0.012, a: 0.45 * sd, rs: 0.032, ra: 0.024, h: 0.0045 + 0.0055 * k });
        B.push({ s: s0 + 0.026, a: 0.3 * sd, rs: 0.032, ra: 0.028, h: -(0.002 + 0.002 * k) });
      }
      // bruising round the break (more on the side the camera sees), a yellow-green fringe comes from the shader
      for (let k = 0; k < 7 + sev * 2; k++) {
        const a = (R() - 0.35) * 2.2, ds = (R() - 0.5) * 0.07;
        S.layers.paint('bruise', uv(s0 + ds, a), [(0.018 + R() * 0.026), (0.012 + R() * 0.016)], 0.12 + sev * 0.05, { hardness: 0, grain: 0.35, grainScale: 70, angle: R() * Math.PI });
      }
      S.layers.paint('bruise', uv(s0, 0.3), [0.034 + sev * 0.006, 0.024], 0.3 + sev * 0.07, { hardness: 0, grain: 0.3, grainScale: 60 });
      S.layers.paint('bruise', uv(s0 - 0.004, 0.4 * this.side), [0.016, 0.012], 0.45 + sev * 0.08, { hardness: 0, grain: 0.3, grainScale: 60 });
      // a few grazes and grime from the fall
      for (let k = 0; k < 3; k++) S.layers.paint('grime', uv(s0 + (R() - 0.5) * 0.2, (R() - 0.3) * 1.6), [0.02 + R() * 0.03, 0.012 + R() * 0.02], 0.08 + R() * 0.08, { hardness: 0, grain: 0.7, grainScale: 160, angle: R() * Math.PI });
      if (!d.open) return;
      // open fracture: a ragged wound over the break
      const wUv = uv(s0 + 0.004, 0.32 * sd), seed = hash(d.name || 'w') % 100000;
      this.wound = S.wounds.add({ type: 'laceration', uv: wUv, angle: 0.25 * sd, length: 0.03, gape: 0.0045, depth: 0.009, jagged: 0.7, rim: 0.8, seed });
      if (d.dressed) { this.makeDressing(s0 + 0.004, 0.32 * sd); return; }
      S.layers.splat('blood', wUv, 0.004, 0.75, { seed: 3, count: 6 });
      S.fluids.bleed(this.wound, 1.4);   // a slow ooze from the wound (runs down round the limb)
      for (let k = 0; k < 9; k++) { const ds = (R() - 0.5) * 0.05, da = (R() - 0.2) * 0.9; S.layers.splat('blood', uv(s0 + ds, 0.32 * sd + da), 0.0015 + R() * 0.0025, 0.2 + R() * 0.3, { seed: 10 + k, count: 4 }); }
      for (let k = 0; k < 3; k++) S.layers.stroke('clot', uv(s0 + (R() - 0.5) * 0.02, 0.4 * sd), uv(s0 + (R() - 0.5) * 0.03, 1.2 * sd + (R() - 0.5) * 0.3), 0.0008, 0.07, { hardness: 0.4, grain: 0.4, grainScale: 120 });
      // the bone end in the wound
      const P = V3(), N = V3();
      this.surfPt(s0 + 0.004, 0.32 * sd, -0.004, P, N);
      const bg = this.keep(new THREE.CapsuleGeometry(0.0042, 0.012, 6, 14));
      {
        const p = bg.attributes.position, col = new Float32Array(p.count * 3);
        for (let i = 0; i < p.count; i++) {
          const y = p.getY(i);
          // a broken, jagged end: the top is chipped
          if (y > 0.006) p.setY(i, y - 0.0018 * Math.abs(Math.sin(p.getX(i) * 900 + p.getZ(i) * 700)));
          const b = smooth(0.004, -0.004, y);
          col[i * 3] = lerp(1, 0.55, b); col[i * 3 + 1] = lerp(0.97, 0.1, b); col[i * 3 + 2] = lerp(0.9, 0.08, b);
        }
        bg.setAttribute('color', new THREE.BufferAttribute(col, 3));
        bg.computeVertexNormals();
      }
      const bone = new THREE.Mesh(bg, this.M.bone);
      bone.position.copy(P);
      bone.quaternion.setFromUnitVectors(V3(0, 1, 0), N.clone().add(V3(0.7 * sd, 0, 0)).normalize());
      bone.castShadow = true; bone.receiveShadow = true;
      this.S.scene.add(bone);
    }
    // a gauze dressing already on an open wound, moulded to the skin, blood showing through
    makeDressing(s0, a0) {
      const NP = 14, size = 0.07, geo = this.keep(gridGeo(NP, NP)), pos = geo.attributes.position.array;
      const P = V3(), N = V3(), R = this.R;
      for (let j = 0; j <= NP; j++) for (let i = 0; i <= NP; i++) {
        const k = j * (NP + 1) + i, x = (i / NP - 0.5) * size, y = (j / NP - 0.5) * size;
        const e = 0.006, b = smooth(-size / 2, -size / 2 + e, x) * (1 - smooth(size / 2 - e, size / 2, x)) * smooth(-size / 2, -size / 2 + e, y) * (1 - smooth(size / 2 - e, size / 2, y));
        this.surfPt(s0 + x, a0 + y / R, 0.0006 + 0.003 * Math.sqrt(b), P, N);
        pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
      }
      geo.computeVertexNormals();
      const c = cvs(128, 128), x = c.getContext('2d');
      x.fillStyle = '#efebe2'; x.fillRect(0, 0, 128, 128);
      const g = x.createRadialGradient(62, 66, 2, 64, 64, 40); g.addColorStop(0, 'rgba(110,8,10,.85)'); g.addColorStop(0.5, 'rgba(140,16,14,.5)'); g.addColorStop(1, 'rgba(150,30,20,0)');
      x.fillStyle = g; x.beginPath(); x.ellipse(64, 64, 44, 30, 0.3, 0, TAU); x.fill();
      const pad = padTex();
      const mat = this.keep(new THREE.MeshPhysicalMaterial({ map: this.M.tex(c, true, null, true), normalMap: this.M.tex(pad.normal, false, [3, 3]), normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.95, sheen: 0.5, sheenColor: new THREE.Color(1, 1, 1) }));
      const m = new THREE.Mesh(geo, mat);
      m.castShadow = true; m.receiveShadow = true;
      this.S.scene.add(m);
    }

    /* ─────────────── past the patch: lower leg / forearm, foot / hand, digits, nails ─────────────── */
    makeDistal() {
      const S = this.S, R = this.R, x0 = this.xEnd, yb = this.yb, end = this.limbAt(x0);
      const rings = [];
      const ring = (x, ry, rz, ur) => ({ c: V3(x, yb + ry, 0), U: V3(0, 1, 0), Z: V3(0, 0, 1), hu: ry, hz: rz, eu: 2, ed: 2, ur, rho: R * Math.sqrt((ry * rz) / (end.ry * end.rz)) });
      rings.push(ring(x0, end.ry, end.rz, 0));
      let xs = x0, ry = end.ry, rz = end.rz;
      // upper segments: the rest of the lower leg / forearm down to the ankle / wrist
      if (this.upper) {
        const leg = this.kind === 'leg', Lsh = leg ? 0.21 : 0.05, n = leg ? 9 : 3;
        const rA = leg ? 0.0435 : 0.034, eA = leg ? 0.95 : 0.8;
        for (let i = 1; i <= n; i++) {
          const f = i / n, x = x0 + Lsh * f;
          const r = lerp(end.rz, rA, smooth(0.25, 1, f)) * (leg ? 1 + 0.04 * gauss(f - 0.2, 0.25) : 1);
          const e = lerp(end.ry / end.rz, eA, smooth(0.3, 1, f));
          rings.push(ring(x, r * e, r, x - x0));
          xs = x; ry = r * e; rz = r;
        }
      }
      const twist = (this.angle || 0) * Math.PI / 180 * 0.7 * this.side;
      const body = this.kind === 'leg' ? this.footRings(xs, ry, rz, rings[rings.length - 1].ur, twist) : this.handRings(xs, ry, rz, rings[rings.length - 1].ur, twist);
      body.rings.forEach((rg, i) => { if (i > 0) rings.push(rg); });
      const geo = this.keep(loftGeo(rings, 40, this.W, this.H));
      const mesh = new THREE.Mesh(geo, S.skin.material);
      mesh.castShadow = true; mesh.receiveShadow = true; mesh.frustumCulled = false;
      S.scene.add(mesh);
      this.distal = { mesh, digits: [], nails: [] };
      body.digits.forEach(dg => {
        const g = new THREE.Group();
        g.position.copy(dg.pivot);
        const rel = dg.rings.map(r => Object.assign({}, r, { c: r.c.clone().sub(dg.pivot) }));
        const m = new THREE.Mesh(this.keep(loftGeo(rel, 18, this.W, this.H)), S.skin.material);
        m.castShadow = true; m.receiveShadow = true; m.frustumCulled = false;
        g.add(m);
        // the nail: a thin domed plate on the back of the last bone
        const nr = dg.nail;
        const mat = this.keep(new THREE.MeshPhysicalMaterial({ color: this.nailColor(1, 0), roughness: 0.32, clearcoat: 0.85, clearcoatRoughness: 0.14, sheen: 0.2, sheenColor: new THREE.Color(1, 0.9, 0.9) }));
        const ng = this.keep(new THREE.SphereGeometry(1, 20, 8, 0, TAU, 0, Math.PI / 2));
        const nail = new THREE.Mesh(ng, mat);
        const X = nr.Z.clone().negate(), Y = nr.U.clone(), Zt = nr.T.clone();
        nail.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(X, Y, Zt));
        nail.position.copy(nr.c).sub(dg.pivot);
        nail.scale.set(nr.w / 2, 0.0011, nr.l / 2);
        nail.castShadow = false; nail.receiveShadow = true;
        g.add(nail);
        S.scene.add(g);
        const rec = { group: g, axis: dg.axis.clone(), nail, mat, big: !!dg.big, blanch: 0, wig: dg.wig || 0 };
        this.distal.digits.push(rec);
        this.distal.nails.push(rec);
      });
      // the nail checked first: the big toe / the middle finger
      this.checkNail = this.distal.nails.find(n => n.big) || this.distal.nails[0];
    }
    // the foot (heel on the blanket, toes up), right foot: big toe toward −z (side −1 mirrors it)
    footRings(x0, ry0, rz0, ur0, twist) {
      const yb = this.yb, sd = this.side, sc = this.footScale(), R = this.R;
      // dorsal (D) and plantar (P) outline points [x past the ankle, y above the blanket] and the half width
      const D = [[0, 2 * ry0], [0.004, 2 * ry0 + 0.003], [0.009, 2 * ry0 + 0.009], [0.013, 0.106], [0.016, 0.12], [0.022, 0.14], [0.032, 0.162], [0.042, 0.187], [0.047, 0.199]];
      const Pp = [[0, 0], [0.03, -0.001], [0.056, 0.006], [0.066, 0.03], [0.067, 0.06], [0.066, 0.1], [0.066, 0.14], [0.066, 0.18], [0.064, 0.197]];
      const HZ = [rz0, rz0 * 1.1, 0.034, 0.033, 0.034, 0.038, 0.042, 0.046, 0.044];
      const axisY = yb + ry0;
      const rot = (v, a, isPoint) => {
        if (!a) return v;
        const y = isPoint ? v.y - axisY : v.y, z = v.z, c = Math.cos(a), s = Math.sin(a);
        v.y = (isPoint ? axisY : 0) + y * c - z * s; v.z = y * s + z * c;
        return v;
      };
      const rings = [];
      let ur = ur0, prev = null;
      const sz = (i, v) => (i >= 2 ? v * sc : v);
      for (let i = 0; i < D.length; i++) {
        const dp = V3(x0 + sz(i, D[i][0]), yb + sz(i, D[i][1]), 0), pp = V3(x0 + sz(i, Pp[i][0]), yb + sz(i, Pp[i][1]), 0);
        const c = dp.clone().add(pp).multiplyScalar(0.5), U = dp.clone().sub(pp), hu = U.length() / 2;
        U.normalize();
        const Z = V3(0, 0, 1), tw = twist * smooth(1, 3, i);
        rot(c, tw, true); rot(U, tw, false); rot(Z, tw, false);
        if (prev) ur += c.distanceTo(prev);
        prev = c.clone();
        const hz = sz(i, HZ[i]);
        rings.push({ c, U, Z, hu, hz, eu: i >= 2 ? 2.3 : 2, ed: i >= 2 ? 3.1 : 2, ur, rho: R * Math.sqrt((hu * hz) / (ry0 * rz0)) });
      }
      // round the front of the foot under the toes
      const last = rings[rings.length - 1], Tl = V3().crossVectors(last.U, last.Z).normalize();
      [[0.005, 0.8], [0.009, 0.45], [0.011, 0.08]].forEach(([adv, k]) => rings.push(Object.assign({}, last, { c: last.c.clone().addScaledVector(Tl, adv), hu: last.hu * k, hz: last.hz * k, ur: last.ur + adv, rho: last.rho * k })));
      // toes from the front of the foot: [z, length, radius, back, up, splay]
      const C = last.c, U = last.U, Z = last.Z;
      const TOES = [[-0.025, 0.033, 0.0112, 0.006, 0.0, -0.08], [-0.006, 0.028, 0.0074, 0.004, 0.0012, -0.03], [0.008, 0.025, 0.0069, 0.007, 0.0012, 0.02], [0.02, 0.021, 0.0065, 0.011, 0.0008, 0.07], [0.031, 0.017, 0.006, 0.016, 0.0, 0.13]];
      const digits = TOES.map((t, ti) => {
        const zz = t[0] * sd * sc, len = t[1] * sc, r = t[2] * sc;
        const base = C.clone().addScaledVector(Z, zz).addScaledVector(U, t[4] - 0.002).addScaledVector(Tl, -t[3] * sc);
        const dir = Tl.clone().addScaledVector(Z, t[5] * sd).normalize();
        const curl = ti ? 0.55 : 0.25;
        const pts = [base.clone().addScaledVector(dir, -0.012), base.clone(), base.clone().addScaledVector(dir, len * 0.5).addScaledVector(U, 0.0008),
          base.clone().addScaledVector(dir, len * 0.84).addScaledVector(U, -r * curl * 0.4), base.clone().addScaledVector(dir, len * 0.98).addScaledVector(U, -r * curl)];
        const rr = tubeRings(pts, 10, f => ({ hu: r * lerp(0.74, 0.64, f) * (1 + 0.07 * gauss(f - 0.5, 0.12)), hz: r * lerp(1.0, 0.9, f), eu: 2.3, ed: 2.8 }), U, last.ur, true);
        // the nail on the last third, on the back of the toe
        const k = Math.round(rr.length * 0.6), rk = rr[Math.min(rr.length - 1, 8)];
        void k;
        const big = ti === 0;
        const nail = { c: rk.c.clone().addScaledVector(rk.U, rk.hu * 0.93), U: rk.U.clone(), Z: rk.Z.clone(), T: rk.T.clone(), w: rk.hz * (big ? 1.45 : 1.35), l: len * (big ? 0.42 : 0.34) };
        return { rings: rr, pivot: base.clone(), axis: Z.clone(), nail, big, wig: 0.16 + 0.04 * ti };
      });
      return { rings, digits };
    }
    // the hand, palm down on the end of the splint (forearm: over the palm roll), right hand: thumb toward −z
    handRings(x0, ry0, rz0, ur0, twist) {
      const yb = this.yb, sd = this.side, sc = this.sex === 'f' ? 0.92 : 1, R = this.R, roll = !this.upper;
      // [x past the wrist, bottom, top, half width]
      const RG = [[0, 0, 2 * ry0, rz0], [0.014, 0.003, 2 * ry0 + 0.002, rz0 * 1.06], [0.034, roll ? 0.012 : 0.004, 2 * ry0 + 0.007, rz0 * 1.18],
        [0.055, roll ? 0.024 : 0.005, 2 * ry0 + 0.011, 0.041], [0.074, roll ? 0.03 : 0.006, 2 * ry0 + 0.012, 0.042], [0.085, roll ? 0.029 : 0.006, 2 * ry0 + 0.006, 0.040]];
      const axisY = yb + ry0;
      const rot = (v, a, isPoint) => {
        if (!a) return v;
        const y = isPoint ? v.y - axisY : v.y, z = v.z, c = Math.cos(a), s = Math.sin(a);
        v.y = (isPoint ? axisY : 0) + y * c - z * s; v.z = y * s + z * c;
        return v;
      };
      const rings = [];
      let ur = ur0, prev = null;
      RG.forEach((g, i) => {
        const k = i >= 2 ? sc : 1, x = x0 + g[0] * (i >= 1 ? sc : 1);
        const bot = yb + g[1] * k, top = yb + (i >= 2 ? 2 * ry0 + (g[2] - 2 * ry0) * k : g[2]);
        const c = V3(x, (bot + top) / 2, 0), U = V3(0, 1, 0), Z = V3(0, 0, 1), tw = twist * smooth(1, 3, i);
        rot(c, tw, true); rot(U, tw, false); rot(Z, tw, false);
        if (prev) ur += c.distanceTo(prev);
        prev = c.clone();
        const hu = (top - bot) / 2, hz = g[3] * (i >= 3 ? sc : 1);
        rings.push({ c, U, Z, hu, hz, eu: i >= 2 ? 2.4 : 2, ed: i >= 2 ? 2.8 : 2, ur, rho: R * Math.sqrt((hu * hz) / (ry0 * rz0)) });
      });
      const last = rings[rings.length - 1], Tl = V3().crossVectors(last.U, last.Z).normalize();
      [[0.004, 0.8], [0.007, 0.4], [0.008, 0.06]].forEach(([adv, k]) => rings.push(Object.assign({}, last, { c: last.c.clone().addScaledVector(Tl, adv), hu: last.hu * k, hz: last.hz * k, ur: last.ur + adv, rho: last.rho * k })));
      const knuck = rings[4], C = knuck.c, U = knuck.U, Z = knuck.Z, T4 = V3().crossVectors(U, Z).normalize();
      // fingers: [z, phalanx lengths, radius, splay]
      const FING = [[-0.025, [0.042, 0.025, 0.02], 0.0086, -0.05], [-0.008, [0.046, 0.028, 0.021], 0.0088, -0.01], [0.009, [0.043, 0.026, 0.02], 0.0083, 0.03], [0.025, [0.034, 0.02, 0.018], 0.0074, 0.08]];
      const flex = roll ? [0.3, 0.62, 0.95] : [0.04, 0.12, 0.2];
      const digits = FING.map((f, fi) => {
        const zz = f[0] * sd * sc, r = f[2] * sc;
        const base = C.clone().addScaledVector(Z, zz).addScaledVector(U, 0.003).addScaledVector(T4, 0.004);
        const pts = [base.clone().addScaledVector(T4, -0.014), base.clone()];
        let cur = base.clone(), ph = 0;
        const sp = V3().addScaledVector(Z, f[3] * sd);
        f[1].forEach((L, k) => {
          ph += flex[k];
          const dir = T4.clone().multiplyScalar(Math.cos(ph)).addScaledVector(U, -Math.sin(ph)).add(sp).normalize();
          pts.push(cur.clone().addScaledVector(dir, L * sc * 0.5));
          cur = cur.clone().addScaledVector(dir, L * sc);
          pts.push(cur.clone());
        });
        const rr = tubeRings(pts, 16, t => ({ hu: r * lerp(0.86, 0.72, t) * (1 + 0.07 * gauss(t - 0.42, 0.06) + 0.06 * gauss(t - 0.72, 0.05)), hz: r * lerp(1.04, 0.88, t), eu: 2.3, ed: 2.5 }), U, knuck.ur, true);
        const rk = rr[14];
        const nail = { c: rk.c.clone().addScaledVector(rk.U, rk.hu * 0.94), U: rk.U.clone(), Z: rk.Z.clone(), T: rk.T.clone(), w: rk.hz * 1.45, l: 0.011 * sc };
        return { rings: rr, pivot: base.clone(), axis: Z.clone(), nail, big: fi === 1, wig: 0.2 };
      });
      // the thumb along the side of the palm
      {
        const r = 0.0106 * sc;
        const base = V3(x0 + 0.026 * sc, yb + (roll ? 0.026 : 0.017), -sd * 0.03 * sc);
        rot(base, twist, true);
        const pts = [base.clone().add(V3(-0.01, 0.002, sd * 0.006)), base.clone(), base.clone().add(V3(0.022, -0.004, -sd * 0.011)), base.clone().add(V3(0.04, -0.009, -sd * 0.014)), base.clone().add(V3(0.057, -0.013, -sd * 0.012))];
        const up = V3(0, 0.55, -sd * 0.83).normalize();
        const rr = tubeRings(pts, 12, t => ({ hu: r * lerp(0.86, 0.74, t), hz: r * lerp(1.02, 0.9, t), eu: 2.3, ed: 2.5 }), up, ur0 + 0.03, true);
        const rk = rr[10];
        digits.push({ rings: rr, pivot: base.clone(), axis: V3(0, 1, 0), nail: { c: rk.c.clone().addScaledVector(rk.U, rk.hu * 0.94), U: rk.U.clone(), Z: rk.Z.clone(), T: rk.T.clone(), w: rk.hz * 1.45, l: 0.012 * sc }, big: false, wig: 0.12 });
      }
      return { rings, digits };
    }
    // nail bed colour: perfusion 0 (white, pressed) … 1 (pink); dusk 0..1 (blue-grey behind a tight strap)
    nailColor(perf, dusk) {
      const t = this.tone || 0.3;
      const pink = new THREE.Color().setRGB(lerp(0.88, 0.62, t), lerp(0.58, 0.4, t), lerp(0.56, 0.38, t));
      const white = new THREE.Color().setRGB(lerp(0.95, 0.82, t), lerp(0.91, 0.75, t), lerp(0.86, 0.68, t));
      const blue = new THREE.Color().setRGB(lerp(0.66, 0.5, t), lerp(0.6, 0.46, t), lerp(0.74, 0.56, t));
      const c = white.lerp(pink, clamp(perf, 0, 1));
      return c.lerp(blue, clamp(dusk, 0, 1) * clamp(perf, 0, 1)).convertSRGBToLinear();
    }

    /* ─────────────── the splint (ported from the 2D game's model, now in the scene) ─────────────── */
    makeSplint() {
      const S = this.S, M = this.M, st = this.st;
      const kind = this.kind, L = this.Ls;
      let maxLimb = 0;
      for (let i = 0; i <= 40; i++) maxLimb = Math.max(maxLimb, this.limbHalfZ(this.xT - L / 2 + L * i / 40));
      const th = this.size.wall, depth = this.size.depth;
      const hw0 = Math.max(this.size.width / 2 - th, maxLimb + 0.005);
      const o = this.so = {
        kind, L, th, depth, hw0, flare: 0.3, sig: 0.04, yF: -0.003, yT: -0.003 + depth,
        plate: kind === 'leg' && !this.upper, roll: kind === 'arm' && !this.upper, strapW: STRAP_W[kind],
      };
      o.perim = Math.PI / 2 * Math.sqrt(2 * (hw0 * hw0 + depth * depth)) * 1.12;
      const J = this.d.joints || {};
      const lt = linerTex({
        kind, L, perim: o.perim, sites: st.sites.map(s => ({ x: s.x })),
        print: {
          prox: J.prox || T('j_prox', 'Upper joint'), dist: J.dist || T('j_dist', 'Lower joint'), model: this.d.deviceModel || '',
          name: kind === 'leg' ? T('print_leg', 'Posterior leg splint') : T('print_arm', 'Posterior arm splint'),
          use: T('print_use', 'Single patient use · latex free'), warn: T('print_warn', 'Check pulse below'), warn2: T('print_warn2', 'after every strap'),
        },
      });
      M.foam = this.keep(new THREE.MeshStandardMaterial({ map: M.tex(lt.albedo, true, null, true), normalMap: M.tex(lt.normal, false, null, true), normalScale: new THREE.Vector2(0.75, 0.75), roughness: 0.93, side: THREE.DoubleSide, envMapIntensity: 0.55 }));
      [M.foam.map, M.foam.normalMap].forEach(t => { t.flipY = false; });
      const group = this.splint = new THREE.Group();
      S.scene.add(group);
      this.trough = this.buildTrough(group, [M.foam, M.shell], M.bind, M.cap, false);
      // the outline where it goes (step 1)
      this.ghostG = new THREE.Group();
      S.scene.add(this.ghostG);
      this.ghost = this.buildTrough(this.ghostG, [M.ghost, M.ghost], M.ghost, M.ghost, true);
      this.ghostG.position.set(this.xT, this.yb, 0);
      this.trough.fill(x => this.profile(x, true));
      this.ghost.fill(x => this.profile(x, true));
      this.ghostG.traverse(m => { if (m.isMesh) { m.castShadow = false; m.receiveShadow = false; m.renderOrder = 3; } });
      this.makeOutline();
      // the end: foot plate (leg) / palm roll (forearm)
      if (o.plate) {
        const w = hw0 * 2 * (1 + 0.15) + th * 2 + 0.008, hgt = 0.2;
        const sh = new THREE.Shape(), r = 0.018;
        sh.moveTo(-w / 2 + r, 0); sh.lineTo(w / 2 - r, 0); sh.quadraticCurveTo(w / 2, 0, w / 2, r); sh.lineTo(w / 2, hgt - r); sh.quadraticCurveTo(w / 2, hgt, w / 2 - r, hgt);
        sh.lineTo(-w / 2 + r, hgt); sh.quadraticCurveTo(-w / 2, hgt, -w / 2, hgt - r); sh.lineTo(-w / 2, r); sh.quadraticCurveTo(-w / 2, 0, -w / 2 + r, 0);
        const g = this.keep(new THREE.ExtrudeGeometry(sh, { depth: 0.012, bevelEnabled: true, bevelThickness: 0.003, bevelSize: 0.003, bevelSegments: 3, curveSegments: 6 }));
        g.applyMatrix4(new THREE.Matrix4().set(0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1));
        const plate = new THREE.Mesh(g, M.shell);
        plate.position.set(L / 2 - 0.004, o.yF - th, 0);
        group.add(plate);
        const pf = new THREE.Mesh(this.keep(new THREE.BoxGeometry(0.01, hgt - 0.03, w - 0.024)), M.plateFoam);
        pf.position.set(L / 2 - 0.009, o.yF - th + hgt / 2 + 0.008, 0);
        group.add(pf);
        for (const sg of [-1, 1]) {
          const rib = new THREE.Mesh(this.keep(new THREE.BoxGeometry(0.018, 0.008, 0.022)), M.tab);
          rib.position.set(L / 2 + 0.002, o.yF - th + hgt - 0.004, sg * (w / 2 - 0.02));
          group.add(rib);
        }
      }
      if (o.roll) {
        const roll = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.017, 0.017, hw0 * 2 + 0.004, 28, 1)), M.roll);
        roll.rotation.x = Math.PI / 2;
        roll.position.set(L / 2 - 0.03, o.yF + 0.017, 0);
        group.add(roll);
      }
      // padding: two soft rolls at each joint, between the wall and the limb
      const pg = this.wadGeo();
      this.pads = st.sites.map(() => [-1, 1].map(() => { const m = new THREE.Mesh(pg, M.pad); m.castShadow = true; m.receiveShadow = true; m.visible = false; group.add(m); return m; }));
      // straps
      this.straps = st.straps.map((s, i) => this.buildStrap(group, i));
      group.traverse(m => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; } });
      // where the splint starts: on the blanket beside the limb (your side), a little off its mark
      this.sp = { x: this.xT - 0.07, z: hw0 + th + maxLimb + 0.035, under: false, drop: 0, drag: null, hold: 0, ok: false, moved: false, locked: false, anim: null };
      this.sp.z0 = this.sp.z; this.sp.x0 = this.sp.x;
      this.placeSplint(0);
    }
    // where the splint goes: a dashed band round both rims and across both ends (over the limb, so the ends show)
    makeOutline() {
      const o = this.so, L = o.L, th = o.th, N = 48, rim = [];
      for (let i = 0; i <= N; i++) { const x = -L / 2 + L * i / N, pr = this.profile(x, true), hw = pr.hw * (1 + pr.flare) + th * 0.5; rim.push([x, pr.yT + th * 0.6, hw]); }
      const loop = rim.map(p => p.slice());
      for (let i = N; i >= 0; i--) loop.push([rim[i][0], rim[i][1], -rim[i][2]]);
      loop.push(loop[0].slice());
      // the two ends straight across (5 dashes each) are part of the loop's turns: add them densely
      const pts = [];
      for (let i = 0; i < loop.length - 1; i++) {
        const a = loop[i], b = loop[i + 1], n = Math.max(1, Math.round(Math.hypot(b[0] - a[0], b[2] - a[2]) / 0.012));
        for (let k = 0; k < n; k++) { const f = k / n; pts.push([lerp(a[0], b[0], f), lerp(a[1], b[1], f), lerp(a[2], b[2], f)]); }
      }
      pts.push(loop[loop.length - 1]);
      const pos = [], w = 0.0024;
      for (let i = 0; i < pts.length - 1; i += 2) {
        const a = pts[i], b = pts[i + 1], dx = b[0] - a[0], dz = b[2] - a[2], l = Math.hypot(dx, dz) || 1, px = -dz / l * w, pz = dx / l * w;
        pos.push(a[0] + px, a[1], a[2] + pz, a[0] - px, a[1], a[2] - pz, b[0] + px, b[1], b[2] + pz, b[0] + px, b[1], b[2] + pz, a[0] - px, a[1], a[2] - pz, b[0] - px, b[1], b[2] - pz);
      }
      const g = this.keep(new THREE.BufferGeometry());
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      this.outlineMat = this.keep(new THREE.MeshBasicMaterial({ color: 0x2fe0d0, transparent: true, opacity: 0.95, depthTest: false, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
      const m = new THREE.Mesh(g, this.outlineMat);
      m.renderOrder = 19; m.frustumCulled = false;
      this.ghostG.add(m);
    }
    // the channel: inner liner, shell, bound rims, end faces. fill(profileFn) rebuilds its shape
    buildTrough(group, mats, bindMat, capMat, nominal) {
      const o = this.so, NX = 84, K = 22, RC = 5, RING = 2 * (K + 1) + 2 * RC, BV = RC + 2;
      const keep = x => this.keep(x);
      const geo = keep(new THREE.BufferGeometry());
      const pos = new Float32Array((NX + 1) * RING * 3), uv = new Float32Array((NX + 1) * RING * 2);
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      const foam = [], shell = [];
      for (let i = 0; i < NX; i++) for (let j = 0; j < RING; j++) {
        const isFoam = j < K, isShell = j >= K + RC + 1 && j <= 2 * K + RC;
        if (!isFoam && !isShell) continue;
        const j2 = (j + 1) % RING, a = i * RING + j, b = i * RING + j2, c = (i + 1) * RING + j, dd = (i + 1) * RING + j2;
        (isFoam ? foam : shell).push(a, dd, b, a, c, dd);
      }
      geo.setIndex(foam.concat(shell));
      geo.addGroup(0, foam.length, 0);
      geo.addGroup(foam.length, shell.length, 1);
      for (let i = 0; i <= NX; i++) for (let j = 0; j < RING; j++) {
        const q = (i * RING + j) * 2;
        uv[q] = j <= K ? j / K : (j - (K + RC + 1)) / K; uv[q + 1] = i / NX;
      }
      const mesh = new THREE.Mesh(geo, mats);
      group.add(mesh);
      const RIM_F = Array.from({ length: BV }, (_, r) => K + r), RIM_N = Array.from({ length: BV }, (_, r) => (2 * K + RC + 1 + r) % RING);
      const bgeo = keep(new THREE.BufferGeometry());
      bgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array((NX + 1) * 2 * BV * 3), 3));
      const buv = new Float32Array((NX + 1) * 2 * BV * 2), bi = [];
      for (let i = 0; i <= NX; i++) for (let sd = 0; sd < 2; sd++) for (let r = 0; r < BV; r++) {
        const q = ((i * 2 + sd) * BV + r) * 2;
        buv[q] = r / (BV - 1); buv[q + 1] = (o.L * i / NX) / 0.05;
        if (i < NX && r < BV - 1) { const a = (i * 2 + sd) * BV + r, b = a + 1, c = ((i + 1) * 2 + sd) * BV + r, d = c + 1; bi.push(a, d, b, a, c, d); }
      }
      bgeo.setAttribute('uv', new THREE.BufferAttribute(buv, 2));
      bgeo.setIndex(bi);
      const bind = new THREE.Mesh(bgeo, bindMat);
      group.add(bind);
      const cgeo = keep(new THREE.BufferGeometry());
      cgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(2 * RING * 3), 3));
      const ci = [], outer = k => K + RC + 1 + (K - k);
      for (let e = 0; e < 2; e++) {
        const b = e * RING;
        for (let k = 0; k < K; k++) ci.push(b + k, b + k + 1, b + outer(k + 1), b + k, b + outer(k + 1), b + outer(k));
        for (let r = 0; r < RC; r++) ci.push(b + K, b + K + 1 + r, b + K + 2 + r);
        for (let r = 0; r < RC; r++) ci.push(b + 2 * K + RC + 1, b + 2 * K + RC + 2 + r, b + ((2 * K + RC + 3 + r) % RING));
      }
      cgeo.setIndex(ci);
      const caps = new THREE.Mesh(cgeo, capMat);
      group.add(caps);
      const buf = new Float32Array(RING * 2);
      const self = this;
      return {
        mesh, bind, caps,
        fill(prof) {
          const p = geo.attributes.position.array, bp = bgeo.attributes.position.array, cp = cgeo.attributes.position.array;
          for (let i = 0; i <= NX; i++) {
            const x = -o.L / 2 + o.L * i / NX, pr = prof(x);
            self.ringZY(pr, o.th, buf, K, RC);
            for (let j = 0; j < RING; j++) {
              const k = (i * RING + j) * 3;
              p[k] = x; p[k + 1] = buf[j * 2 + 1]; p[k + 2] = buf[j * 2];
              if (i === 0 || i === NX) { const e = (i === 0 ? 0 : 1) * RING + j; cp[e * 3] = x; cp[e * 3 + 1] = p[k + 1]; cp[e * 3 + 2] = p[k + 2]; }
            }
            for (let sd = 0; sd < 2; sd++) {
              const rim = sd ? RIM_N : RIM_F;
              for (let r = 0; r < BV; r++) { const j = rim[r], b = ((i * 2 + sd) * BV + r) * 3; bp[b] = x; bp[b + 1] = buf[j * 2 + 1] + 0.0003; bp[b + 2] = buf[j * 2]; }
            }
          }
          [geo, bgeo, cgeo].forEach(g => { g.attributes.position.needsUpdate = true; g.computeVertexNormals(); g.computeBoundingSphere(); });
        },
        nominal,
      };
    }
    // the channel's cross-section [z, y] (inner near rim → floor → far rim, far rim cap, outer, near rim cap)
    ringZY(pr, th, out, K, RC) {
      let n = 0;
      const hwTop = pr.hw * (1 + pr.flare), depth = pr.yT - pr.yF;
      for (let k = 0; k <= K; k++) { const ph = Math.PI / 2 - Math.PI * k / K, s = Math.sin(ph), c = Math.cos(ph); out[n++] = pr.hw * s * (1 + pr.flare * (1 - c)); out[n++] = pr.yF + depth * (1 - c); }
      for (let r = 1; r <= RC; r++) { const a = Math.PI * r / (RC + 1); out[n++] = -(hwTop + th / 2) + (th / 2) * Math.cos(a); out[n++] = pr.yT + (th / 2) * Math.sin(a); }
      for (let k = K; k >= 0; k--) { const ph = Math.PI / 2 - Math.PI * k / K, s = Math.sin(ph), c = Math.cos(ph); out[n++] = pr.hw * s * (1 + pr.flare * (1 - c)) + th * s; out[n++] = pr.yF + depth * (1 - c) - th * c; }
      for (let r = 1; r <= RC; r++) { const a = Math.PI * r / (RC + 1); out[n++] = (hwTop + th / 2) + (th / 2) * Math.cos(a); out[n++] = pr.yT + (th / 2) * Math.sin(a); }
      return out;
    }
    // the channel at splint x: half width, flare, rim / floor height. Shaped: the walls close on the limb
    // between the pressed points; the padding at the joints pushes them out again; past the teal band = a dent
    profile(x, nominal) {
      const o = this.so, st = this.st, t = (x + o.L / 2) / o.L;
      let shaped = 0, over = 0, padded = 0;
      if (!nominal && this.placed) {
        const pts = st.points, z0 = this.tune.shapeZone[0], z1 = this.tune.shapeZone[1], sig = o.sig;
        const sv = p => Math.min(1, p.f / z0);
        if (x <= pts[0].x) shaped = sv(pts[0]) * Math.exp(-((x - pts[0].x) ** 2) / (2 * sig * sig));
        else if (x >= pts[pts.length - 1].x) { const q = pts[pts.length - 1]; shaped = sv(q) * Math.exp(-((x - q.x) ** 2) / (2 * sig * sig)); }
        else for (let i = 0; i < pts.length - 1; i++) { const a = pts[i], b = pts[i + 1]; if (x >= a.x && x <= b.x) { shaped = lerp(sv(a), sv(b), smooth(0, 1, (x - a.x) / (b.x - a.x))); break; } }
        for (const p of pts) if (p.f > z1) over = Math.max(over, Math.min(1, (p.f - z1) * 30) * Math.exp(-((x - p.x) ** 2) / (2 * 0.025 * 0.025)));
        st.sites.forEach(s => { if (s.padded) padded = Math.max(padded, gauss(x - s.x, 0.034)); });
      }
      const limb = this.placed ? this.limbHalfZ(this.xT + x) : 0;
      let hw = lerp(o.hw0, limb + 0.0026 + 0.0075 * padded, shaped) - 0.004 * over;
      if (this.placed) hw = Math.max(hw, limb + 0.0012 + 0.006 * padded);
      let flare = o.flare * (1 - shaped * 0.85);
      let yT = o.yT + 0.006 * shaped;
      if (o.plate) { hw += 0.006 * smooth(0.8, 0.9, t) * (1 - smooth(0.985, 1, t)) * (1 - shaped); yT += 0.014 * smooth(0.82, 0.97, t); }
      // the ends: the walls come down in a curve (the channel stays open for the limb)
      const rr = 0.035, dp = x + o.L / 2, dd = o.L / 2 - x;
      let k = 1;
      if (dp < rr) { const q = 1 - dp / rr; k = Math.min(k, Math.sqrt(Math.max(0, 1 - q * q))); }
      if (!o.plate && dd < rr) { const q = 1 - dd / rr; k = Math.min(k, Math.sqrt(Math.max(0, 1 - q * q))); }
      yT = o.yF + (yT - o.yF) * (0.42 + 0.58 * k);
      flare *= 0.5 + 0.5 * k;
      return { hw, flare, yT, yF: o.yF };
    }
    refillTrough() { this.trough.fill(x => this.profile(x, false)); this.strapsStale = true; }
    // where the splint is: beside the limb on the blanket, or under it (dropped into the blanket)
    placeSplint(drop) {
      const sp = this.sp, o = this.so;
      const yTable = this.clothY + 0.002 - (o.yF - o.th);
      const dip = (o.depth + 0.02) * Math.sin(Math.PI * clamp(drop, 0, 1)) * (sp.anim ? 1 : 0);
      this.splint.position.set(sp.x, lerp(yTable, this.yb, clamp(drop, 0, 1)) - dip, sp.z);
      this.splint.updateMatrixWorld(true);
    }

    /* ── straps: riveted on your side of the splint, lying open on the blanket; wrapped over the limb to
          the D-ring on the far side, the tail folded back over the top with its numbered pull tab ── */
    buildStrap(group, i) {
      const M = this.M, o = this.so, SM = 40;
      const mk = n => {
        const geo = this.keep(new THREE.BufferGeometry());
        const pos = new Float32Array(n * 4 * 3), uv = new Float32Array(n * 4 * 2), idx = [];
        for (let k = 0; k < n - 1; k++) {
          const a = k * 4, b = (k + 1) * 4;
          idx.push(a, b, a + 1, a + 1, b, b + 1, a + 2, a + 3, b + 2, a + 3, b + 3, b + 2, a, a + 2, b, a + 2, b + 2, b, a + 1, b + 1, a + 3, a + 3, b + 1, b + 3);
        }
        for (let k = 0; k < n; k++) for (let q = 0; q < 4; q++) { uv[(k * 4 + q) * 2] = q % 2; uv[(k * 4 + q) * 2 + 1] = k / (n - 1); }
        geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
        geo.setIndex(idx);
        const m = new THREE.Mesh(geo, M.strap);
        m.frustumCulled = false;
        group.add(m);
        return m;
      };
      const body = mk(SM), tail = mk(16);
      tail.visible = false;
      const tab = new THREE.Group();
      tab.add(new THREE.Mesh(this.keep(new THREE.BoxGeometry(o.strapW + 0.012, 0.016, 0.004)), M.tab));
      for (const dx of [-1, 1]) { const rv = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.0032, 0.0032, 0.0016, 14)), M.metal); rv.rotation.x = Math.PI / 2; rv.position.set(dx * o.strapW * 0.3, 0, 0.0026); tab.add(rv); }
      group.add(tab);
      const dring = new THREE.Group();
      const arc = new THREE.Mesh(this.keep(new THREE.TorusGeometry(o.strapW * 0.56, 0.0023, 8, 26, Math.PI)), M.metal);
      arc.scale.set(1, 0.35, 1);
      dring.add(arc);
      const bar = new THREE.Mesh(this.keep(new THREE.CylinderGeometry(0.0023, 0.0023, o.strapW * 1.12, 10)), M.metal);
      bar.rotation.z = Math.PI / 2; dring.add(bar);
      dring.visible = false;
      group.add(dring);
      const tm = this.keep(new THREE.MeshPhysicalMaterial({ map: M.tex(tabTex(i + 1), true, null, true), roughness: 0.45, clearcoat: 0.5, clearcoatRoughness: 0.3 }));
      const pull = new THREE.Mesh(this.keep(new THREE.BoxGeometry(o.strapW * 0.72, 0.0032, 0.024)), [M.tab, M.tab, tm, M.tab, M.tab, M.tab]);
      group.add(pull);
      return { body, tail, tab, dring, pull, SM, key: '', path: null };
    }
    // the strap's centre line [z, y] in the splint's frame: open (k 0) → wrapped (k 1), the tail when wrapped
    strapPaths(i, needWrap = true) {
      const st = this.st, s = st.straps[i], o = this.so, x = s.x;
      const pr = this.profile(x, !this.placed), hwTop = pr.hw * (1 + pr.flare), th = o.th;
      const zTab = hwTop + th + 0.0024, yTab = pr.yT - 0.014;
      const gy = this.splint.position.y, gx = this.splint.position.x + x, gz = this.splint.position.z;
      const yC = z => this.clothH(gx, gz + z) + 0.0022 - gy;
      const open = [[zTab, yTab], [zTab + 0.0025, yTab - 0.012], [zTab + 0.006, Math.max(yC(zTab + 0.006) + 0.005, o.yF - th - 0.004)], [zTab + 0.015, yC(zTab + 0.015)]];
      for (let k = 1; k <= 5; k++) { const z = zTab + 0.015 + k * 0.019; open.push([z, yC(z)]); }
      const Lm = this.placed ? this.limbAt(this.xT + x) : { ry: this.R, rz: this.R };
      const zD = -(hwTop + th + 0.0035), yD = pr.yT - 0.012;
      // still lying open: no wrapped path to build (the skin hull is the costly part, and the trough is
      // refilled every frame while the walls are shaped)
      if (!needWrap) return { open, wrap: open, zD, yD, cy: Lm.ry, hull: null };
      const tn = s.tension || 0, cl = 0.0026 - 0.0019 * tn;
      const hullPts = [[hwTop + th * 0.5, pr.yT + th * 0.5 + 0.0016]];
      const P = V3(), N = V3();
      for (let k = 0; k <= 32; k++) {
        const a = Math.PI / 2 - Math.PI * k / 32;
        if (this.placed) {
          // the skin under the strap's whole width and a little past its edges (a knee cap or ankle bone
          // just beside the strap must not stand above it and show through)
          for (const dx of [-0.66, -0.33, 0, 0.33, 0.66]) { this.surfPt(Math.min(this.xT + x + dx * o.strapW, this.xEnd - 0.001), a, cl, P, N); hullPts.push([P.z, P.y - this.yb]); }
        } else hullPts.push([(Lm.rz + cl) * Math.sin(a), Lm.ry + (Lm.ry + cl) * Math.cos(a)]);
      }
      hullPts.push([-(hwTop + th * 0.5), pr.yT + th * 0.5 + 0.0016]);
      const hull = upperHull(hullPts);
      const wrap = [[zTab, yTab], [hwTop + th + 0.0014, pr.yT - 0.002]].concat(hull, [[-(hwTop + th + 0.0014), pr.yT - 0.002], [zD, yD]]);
      return { open, wrap, zD, yD, cy: Lm.ry, hull };
    }
    // rebuild a strap's meshes for its state (k, tension)
    fillStrap(i) {
      const st = this.st, s = st.straps[i], o = this.so, sm = this.straps[i], SM = sm.SM;
      const P = this.strapPaths(i, s.k > 0);
      const A = resample(P.open, SM), B = s.k > 0 ? resample(P.wrap, SM) : A;
      const k = smooth(0, 1, s.k), w2 = o.strapW / 2, h = 0.0024, x = s.x;
      const pts = [];
      for (let j = 0; j < SM; j++) {
        const u = j / (SM - 1), lift = Math.sin(Math.PI * k) * 0.07 * u;
        pts.push([lerp(A[j][0], B[j][0], k), lerp(A[j][1], B[j][1], k) + lift]);
      }
      const ribbon = (mesh, path, outward) => {
        const n = path.length, pos = mesh.geometry.attributes.position.array;
        for (let j = 0; j < n; j++) {
          const p0 = path[Math.max(0, j - 1)], p1 = path[Math.min(n - 1, j + 1)];
          let tz = p1[0] - p0[0], ty = p1[1] - p0[1];
          const tl = Math.hypot(tz, ty) || 1; tz /= tl; ty /= tl;
          let nz = ty, ny = -tz;
          const oz = path[j][0], oy = path[j][1] - P.cy;
          if (outward ? nz * oz + ny * oy < 0 : ny < 0) { nz = -nz; ny = -ny; }
          const z = path[j][0], y = path[j][1], q = j * 12;
          pos[q] = x - w2; pos[q + 1] = y + ny * h / 2; pos[q + 2] = z + nz * h / 2;
          pos[q + 3] = x + w2; pos[q + 4] = y + ny * h / 2; pos[q + 5] = z + nz * h / 2;
          pos[q + 6] = x - w2; pos[q + 7] = y - ny * h / 2; pos[q + 8] = z - nz * h / 2;
          pos[q + 9] = x + w2; pos[q + 10] = y - ny * h / 2; pos[q + 11] = z - nz * h / 2;
        }
        mesh.geometry.attributes.position.needsUpdate = true;
        mesh.geometry.computeVertexNormals();
        mesh.geometry.computeBoundingSphere();
      };
      ribbon(sm.body, pts, k > 0.5);
      sm.path = pts;
      sm.tab.position.set(x, P.open[0][1], P.open[0][0] + 0.0004);
      sm.tab.rotation.set(0, 0, 0);
      const wrapped = s.k >= 0.999;
      sm.dring.visible = wrapped;
      sm.dring.position.set(x, P.yD, P.zD);
      sm.dring.rotation.set(-Math.PI / 2, 0, 0);
      sm.tail.visible = wrapped;
      if (wrapped) {
        // the tail: back up from the D-ring over the far rim and along the top, longer the more it is pulled
        const rev = P.wrap.slice().reverse(), Lt = 0.03 + 0.05 * (s.tension || 0);
        const path = [], off = 0.0027;
        let acc = 0;
        path.push([rev[0][0] - 0.003, rev[0][1]]);
        for (let j = 1; j < rev.length && acc < Lt; j++) {
          const seg = Math.hypot(rev[j][0] - rev[j - 1][0], rev[j][1] - rev[j - 1][1]);
          const f = Math.min(1, (Lt - acc) / Math.max(1e-6, seg));
          const z = lerp(rev[j - 1][0], rev[j][0], f), y = lerp(rev[j - 1][1], rev[j][1], f);
          const dz = z, dy = y - P.cy, dl = Math.hypot(dz, dy) || 1;
          path.push([z + dz / dl * off, y + dy / dl * off]);
          acc += seg * f;
        }
        const tp = resample(path.length > 1 ? path : [path[0], [path[0][0] + 0.01, path[0][1]]], 16);
        ribbon(sm.tail, tp, true);
        const e = tp[tp.length - 1], e0 = tp[tp.length - 2];
        sm.pull.position.set(x, e[1] + 0.0022, e[0]);
        sm.pull.rotation.set(-Math.atan2(e[1] - e0[1], e[0] - e0[0]) + Math.PI, 0, 0);
      } else {
        const e = pts[SM - 1], e0 = pts[SM - 2];
        sm.pull.position.set(x, e[1] + 0.0022, e[0] + 0.006);
        sm.pull.rotation.set(-Math.atan2(e[1] - e0[1], e[0] - e0[0]), 0, 0);
      }
    }
    updateStraps(force) {
      this.st.straps.forEach((s, i) => {
        const key = `${s.k.toFixed(3)}|${(s.tension || 0).toFixed(3)}|${this.splint.position.y.toFixed(4)}|${this.placed ? 1 : 0}`;
        const sm = this.straps[i];
        if (force || this.strapsStale || key !== sm.key) { sm.key = key; this.fillStrap(i); }
      });
      this.strapsStale = false;
    }
    // a soft wad of cotton padding (unit size: 1 along x, 1 up, 1 thick; scaled where it is used)
    wadGeo() {
      if (this._wad) return this._wad;
      const g = this.keep(new THREE.SphereGeometry(1, 30, 18)), p = g.attributes.position, r = rng(77);
      const lumps = Array.from({ length: 9 }, () => [r() * 2 - 1, r() * 2 - 1, r() * 2 - 1, 0.05 + r() * 0.08]);
      for (let i = 0; i < p.count; i++) {
        const v = V3(p.getX(i), p.getY(i), p.getZ(i));
        let k = 1;
        lumps.forEach(b => { const d = v.x * b[0] + v.y * b[1] + v.z * b[2]; k += b[3] * Math.max(0, d) * Math.sin(d * 6); });
        const sq = t => Math.sign(t) * Math.pow(Math.abs(t), 0.7);
        p.setXYZ(i, sq(v.x) * k, sq(v.y) * k, v.z * k);
      }
      g.computeVertexNormals();
      this._wad = g;
      return g;
    }
    // pads at a site (near and far side, wedged between the wall and the limb at its widest)
    placePads(i, k) {
      const site = this.st.sites[i], s = this.xT + site.x, L = this.limbAt(Math.min(s, this.xEnd));
      const hz = this.limbHalfZ(s);
      this.pads[i].forEach((m, j) => {
        const sg = j ? -1 : 1, pop = 1 + 0.2 * (site.pop || 0);
        m.visible = k > 0.01;
        m.position.set(site.x, L.ry * 0.92, sg * (hz + 0.0042));
        m.rotation.set(sg * 0.12, 0, 0);
        m.scale.set(0.028 * pop, 0.017 * lerp(0.4, 1, k) * pop, 0.0052);
      });
    }

    /* ─────────────── tools: gloved hands, the padding roll in hand, markers ─────────────── */
    makeTools() {
      const S = this.S, keep = x => this.keep(x);
      this.hands = { press: buildHand(this.M, keep, 'press', false), point: buildHand(this.M, keep, 'point', false) };
      Object.values(this.hands).forEach(h => S.scene.add(h.group));
      this.padTool = new THREE.Mesh(this.wadGeo(), this.M.pad);
      this.padTool.scale.set(0.03, 0.007, 0.018);
      this.padTool.castShadow = true; this.padTool.visible = false;
      S.scene.add(this.padTool);
      this.markTex = { ring: this.M.tex(ringTex(), false, null, true), check: this.M.tex(checkTex(), false, null, true) };
      this.marks = new Map();
    }
    // a camera-facing marker of a constant on-screen size (px at 1080p)
    mark(id, pos, kind, color, px, opacity = 1) {
      let m = this.marks.get(id);
      if (!m) {
        const mat = this.keep(new THREE.SpriteMaterial({ map: this.markTex[kind], color, transparent: true, depthTest: false, depthWrite: false, toneMapped: false }));
        m = new THREE.Sprite(mat);
        m.renderOrder = 20;
        this.S.scene.add(m);
        this.marks.set(id, m);
      }
      if (m.material.map !== this.markTex[kind]) m.material.map = this.markTex[kind];
      m.material.color.setHex(color);
      m.material.opacity = opacity;
      m.position.copy(pos);
      const cam = this.S.camera, dist = cam.position.distanceTo(pos);
      m.scale.setScalar((px / 1080) * 2 * dist * Math.tan((cam.fov * Math.PI) / 360));
      m.visible = true;
      m.userData.used = true;
      return m;
    }
    // pose a gloved hand: contact point P, surface normal n, the way the forearm goes (dir), wrist tilt
    poseHand(h, P, n, dir, tilt, press) {
      const d = dir.clone().addScaledVector(n, -dir.dot(n)).normalize();
      const Y = d.clone().multiplyScalar(Math.sin(tilt)).addScaledVector(n, Math.cos(tilt));
      const Z = d.clone().multiplyScalar(-Math.cos(tilt)).addScaledVector(n, Math.sin(tilt));
      const X = V3().crossVectors(Y, Z);
      h.group.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(X, Y, Z));
      h.group.position.copy(P).addScaledVector(n, -(press || 0));
      h.group.visible = true;
    }

    // compile every shader up front behind the loading veil
    prewarm() {
      const S = this.S, shown = [];
      const show = o => { if (o && !o.visible) { o.visible = true; shown.push(o); } };
      Object.values(this.hands).forEach(h => { show(h.group); h.group.position.set(0, -5, 0); });
      show(this.padTool);
      this.pads.forEach(p => p.forEach(show));
      this.straps.forEach(sm => { show(sm.tail); show(sm.dring); });
      this.mark('__w1', V3(0, -5, 0), 'ring', 0xffffff, 10); this.mark('__w2', V3(0, -5, 0), 'check', 0xffffff, 10);
      S.prewarm([], false);
      shown.forEach(o => { o.visible = false; });
      this.marks.forEach(m => { m.visible = false; });
    }

    /* ─────────────── camera ─────────────── */
    // the whole splint in the clear middle of the screen (left of the tool belt, right of the step column)
    frameStep(step, instant) {
      const S = this.S, L = this.Ls;
      const cam = S.camera, aspect = cam.aspect || 16 / 9, hfov = 2 * Math.atan(Math.tan((cam.fov * Math.PI) / 360) * aspect);
      // (a forearm splint: the hand past its end is in the clear middle too, not under the tool belt)
      let x0 = this.xT - L / 2 - 0.02, x1 = this.xT + L / 2 + (this.so.plate ? 0.03 : this.so.roll ? 0.11 : 0.02);
      if (step === 5) {
        // the toes / fingers, close: the foot (toes up) from the knee side; the hand curled over the palm roll
        // from beyond the fingertips (its nails face that way); a hand lying flat from above
        const n = this.checkNail.nail.getWorldPosition(V3());
        const leg = this.kind === 'leg', roll = !!this.so.roll;
        const w = leg ? 0.56 : roll ? 0.5 : 0.48;
        S.controls.limits.distMax = 5;
        S.controls.limits.yaw = roll ? 1.65 : 1.0;   // right-drag looks round from this view (no snap back)
        S.controls.frame(S.stToUv(Math.min(n.x - (leg ? 0.07 : roll ? 0.02 : 0.03), this.W * 0.75), 0.004 * this.side), w,
          { pitch: leg ? 0.86 : roll ? 0.6 : 1.08, yaw: leg ? -0.72 : roll ? 1.45 : -0.1, instant: !!instant });
        this.camOffT.set(leg ? -0.01 : roll ? -0.02 : 0.03, leg ? 0.06 : 0.0, 0);
        if (instant) this.camOff.copy(this.camOffT);
        S.controls.limits.distMax = (w / 2) / Math.tan(hfov / 2) * 1.35;
        return;
      }
      // the splint still lies beside the limb (nearer the camera): a steeper, wider view so it does not fill the screen
      const beside = step === 1 && !this.sp.under;
      if (beside) x1 = Math.max(x1, this.sp.x + L / 2 + 0.02);
      S.controls.limits.yaw = 1.0;
      const cw = x1 - x0, vw = clamp(cw / 0.62, 0.45, 1.25) * (beside ? 1.16 : 1);
      const sc = (x0 + x1) / 2 - 0.05 * vw;
      S.controls.limits.distMax = 5;
      S.controls.frame(S.stToUv(sc, 0), vw, { pitch: beside ? 1.2 : step === 1 ? 1.08 : 1.12, yaw: 0, instant: !!instant });
      // step 1: the splint lies beside the limb (toward you): the view sits a little lower
      this.camOffT.set(0, beside ? -0.075 * vw : -0.02 * vw, 0);
      if (this.st.finished) this.camOffT.set(0.07 * vw, 0.05 * vw, 0);
      if (instant) this.camOff.copy(this.camOffT);
      S.controls.limits.distMax = (vw / 2) / Math.tan(hfov / 2) * 1.3;
      this.view = vw;
    }
    applyCam(dt) {
      const k = 1 - Math.exp(-dt * 6);
      this.camOff.lerp(this.camOffT, k);
      const cam = this.S.camera;
      const right = V3(1, 0, 0).applyQuaternion(cam.quaternion), up = V3(0, 1, 0).applyQuaternion(cam.quaternion);
      cam.position.addScaledVector(right, this.camOff.x).addScaledVector(up, this.camOff.y);
      cam.updateMatrixWorld();
    }

    /* ─────────────── step flow ─────────────── */
    stepNames() {
      return [T('g3_sn_lay', 'Lay the splint'), T('g3_sn_pad', 'Pad the bony points'), T('g3_sn_shape', 'Shape it to the limb'), T('g3_sn_strap', 'Strap it'), T('g3_sn_cms', 'Check below the splint')];
    }
    joints() {
      const J = this.d.joints || {};
      return {
        prox: J.prox || T(`joint_${J.proxKey || 'prox'}`, 'the upper joint'), dist: J.dist || T(`joint_${J.distKey || 'dist'}`, 'the lower joint'),
        cms: J.cms || (this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers')),
      };
    }
    enter(n, instant) {
      this.step = n;
      this.st.step = n <= 1 ? 1 : n <= 3 ? 2 : 3;
      this.phaseT = 0;
      this.press = null; this.pull = null; this.blanch = null;
      this.useHand(null);
      this.padTool.visible = false;
      this.frameStep(n, instant);
      this.pp.set({ step: n, title: this.title(), titleTone: '', text: this.text(), tools: this.toolsFor(), hints: this.hintsFor(n) });
      this.panel(true);
    }
    title() {
      const st = this.st;
      switch (this.step) {
        case 1: return T('g3_sn_lay', 'Lay the splint');
        case 2: return T('g3_sn_pad', 'Pad the bony points');
        case 3: return T('g3_sn_shape', 'Shape it to the limb');
        case 4: return this.badStrap() >= 0 ? T('s3_title_bad', 'Loosen the tight strap') : T('s3_title', 'Strap it in place');
        default: return st.cms.state === 'bad' ? T('cms_head_bad', 'Circulation cut off') : T('s3_title_cms', 'Check below the splint');
      }
    }
    text() {
      const d = this.d, J = this.joints(), K = this.K;
      const reg = (d.regionLabel || '').toLowerCase();
      switch (this.step) {
        case 1: return this.sp.under
          ? T('g3_lay2_t', 'Slide it along until both ends sit past the **%s** and the **%s**, on the outline. Let go and hold still to set it (or {%s}).', J.prox.toLowerCase(), J.dist.toLowerCase(), keyLabel(K.set))
          : T('g3_lay_t', '**Drag the splint** under the **%s** and onto the outline, so it reaches past the **%s** and the **%s**.', reg, J.prox.toLowerCase(), J.dist.toLowerCase());
        case 2: return T('g3_pad_t', '**Click** the marked bony point at the **%s** and at the **%s**: padding goes in on both sides, so nothing hard presses on bone.', J.prox.toLowerCase(), J.dist.toLowerCase());
        case 3: return T('g3_shape_t', '**Hold {LMB}** on each marked point: your hand presses the walls in round the limb. **Let go** while the ring is **teal** - past it leaves a pressure point. {Shift} = gentle.');
        case 4: {
          const b = this.badStrap();
          if (b >= 0) return T('g3_strap_bad_t', 'Strap %s cuts the circulation off. **Hold {LMB}** on it to loosen it and pull it again, then let go on the **teal arc**.', b + 1);
          return T('g3_strap_t', '**Hold {LMB}** on a strap: it wraps over the limb and pulls tight. **Let go** on the **teal arc**. Keep the straps off the break.');
        }
        default: return T('g3_cms_t', '**Hold {LMB}** on a %s nail until it goes white, then **let go** and watch the colour come back. Then they move and feel them.', this.kind === 'leg' ? T('g3_toe', 'toe') : T('g3_finger', 'finger'));
      }
    }
    hintsFor(n) {
      const K = this.K, cam = [
        { keys: [T('g3_k_rmb', 'RMB')], label: T('g3_h_look', 'Look around') },
        { keys: [T('g3_k_wheel', 'Wheel')], label: T('g3_h_zoom', 'Zoom') },
        { keys: ['R'], label: T('g3_h_recentre', 'Recentre') },
      ];
      const own = {
        1: [{ keys: [T('k_drag', 'Drag')], label: T('h_slide', 'Slide') }, { keys: ['←', '→'], label: T('h_nudge', 'Nudge') }, { keys: [keyLabel(K.set)], label: T('h_set', 'Set') }, { keys: [keyLabel(K.reset)], label: T('h_reset', 'Start over') }],
        2: [{ keys: [T('k_click', 'Click')], label: T('g3_h_pad', 'Pad the mark') }],
        3: [{ keys: [T('k_hold', 'Hold')], label: T('h_press', 'Press the wall in') }, { keys: ['Shift'], label: T('h_gentle', 'Gentle') }],
        4: [{ keys: [T('k_hold', 'Hold')], label: T('g3_h_pull', 'Wrap and pull tight') }],
        5: [{ keys: [T('k_hold', 'Hold')], label: T('g3_h_nail', 'Press the nail') }],
      }[n] || [];
      return own.concat(cam);
    }
    toolsFor() {
      const st = this.st, step = this.step || 1;
      const state = n => (st.finished || n < step ? 'done' : n === step ? 'active' : 'locked');
      const pads = st.sites.filter(s => s.padded).length, straps = st.straps.filter(s => s.state === 'locked').length;
      const why = T('g3_f_later', 'Finish the step you are on first.');
      return [
        { key: '1', id: 'splint', label: this.d.deviceModel ? `${T('tool_splint', 'Splint')} ${this.d.deviceModel}` : T('tool_splint', 'Splint'), sub: T('tool_splint_sub', 'Lay & align'), icon: 'splint', state: state(1), why },
        { key: '2', id: 'pad', label: T('tool_pad', 'Padding'), sub: `${pads}/2`, icon: 'gauze', state: state(2), why },
        { key: '3', id: 'shape', label: T('tool_shape', 'Shape'), sub: T('tool_shape_sub', 'Press & hold'), icon: 'hand', state: state(3), why },
        { key: '4', id: 'strap', label: T('tool_strap', 'Straps'), sub: `${straps}/3`, icon: 'cuff', state: state(4), why },
        { key: '5', id: 'cms', label: T('tool_cms', 'Distal check'), sub: T('tool_cms_sub', 'Pulse · move · feel'), icon: 'pulse', state: state(5), why },
      ];
    }
    refreshTools() { this.pp.set({ tools: this.toolsFor() }); }
    pickTool(key) {
      const n = +key || 0;
      if (!this.ready || this.st.finished || !n || n === this.step) return;
      if (n < this.step) this.flashOnce('warn', T('g3_f_done', 'That step is done.'), 1500);
    }
    badStrap() { return this.st.straps.findIndex(s => s.tight && s.state === 'locked'); }
    flashOnce(type, text, ms) { const n = performance.now(); if (this.lastFlash === text && n - this.lastFlashAt < 1800) return; this.lastFlash = text; this.lastFlashAt = n; this.pp.flash(type, text, ms || 2000); }
    cursor(p, text, tone, zone) { this.cur.p = p; this.cur.text = text || ''; this.cur.tone = tone || ''; this.cur.zone = zone || null; }
    stageCursor(cls) { const c = `sg3-stage ${cls || ''}`.trim(); if (this.stage.className !== c) this.stage.className = c; }
    useHand(name) { Object.entries(this.hands || {}).forEach(([k, h]) => { if (k !== name) h.group.visible = false; }); this.handName = name; }
    setShift(on) {
      if (this.shift === on) return;
      this.shift = on;
      // a shaping press changes pace: re-base it at the value it has now
      if (this.press) { const n = this.simMs(); this.press.f0 = this.pressF(n); this.press.t0 = n; this.press.rate = on ? 0.45 : 1; }
    }

    /* ─────────────── screen helpers ─────────────── */
    toPx(v) { const p = this.S.project(v); return { x: p.x * window.innerWidth, y: p.y * window.innerHeight, vis: p.visible }; }
    ptrPx() { return { x: this.S.pointer.x * window.innerWidth, y: this.S.pointer.y * window.innerHeight }; }
    pxScale() { return window.innerHeight / 1080; }
    ray() {
      const S = this.S, rc = this._rc || (this._rc = new THREE.Raycaster());
      rc.setFromCamera(new THREE.Vector2(S.pointer.x * 2 - 1, -(S.pointer.y * 2 - 1)), S.camera);
      return rc.ray;
    }
    hitY(y) {
      const r = this.ray();
      if (Math.abs(r.direction.y) < 1e-5) return null;
      const t = (y - r.origin.y) / r.direction.y;
      return t > 0 ? r.origin.clone().addScaledVector(r.direction, t) : null;
    }
    // the cursor on the visible limb (shape included): march along the ray, then bisect
    hitLimb() {
      const r = this.ray(), P = V3();
      const inside = lam => { P.copy(r.origin).addScaledVector(r.direction, lam); if (P.x < -this.W / 2 || P.x > this.xEnd) return false; const L = this.limbAt(P.x); const dy = (P.y - L.cy) / L.ry, dz = P.z / L.rz; return dy * dy + dz * dz <= 1; };
      let lam = 0.02, prev = 0, hit = false;
      for (let i = 0; i < 400 && lam < 3; i++) { if (inside(lam)) { hit = true; break; } prev = lam; lam += 0.004; }
      if (!hit) return null;
      let lo = prev, hi = lam;
      for (let i = 0; i < 16; i++) { const m = (lo + hi) / 2; if (inside(m)) hi = m; else lo = m; }
      P.copy(r.origin).addScaledVector(r.direction, hi);
      const L = this.limbAt(P.x);
      return { point: P.clone(), s: P.x, a: Math.atan2(P.z / L.rz, (P.y - L.cy) / L.ry) };
    }
    // the splint's frame → world
    sw(x, y, z) { return V3(x, y, z).applyMatrix4(this.splint.matrixWorld); }
    sitePos(i) { const s = this.xT + this.st.sites[i].x, P = V3(), N = V3(); this.surfPt(Math.min(s, this.xEnd - 0.002), 1.0, 0.004, P, N); return P; }
    pointPos(i) { const o = this.so, x = this.st.points[i].x, pr = this.profile(x, false); return this.sw(x, pr.yT + o.th * 0.6 + 0.004, pr.hw * (1 + pr.flare) + o.th * 0.5); }
    // where a strap's marker sits: wrapped, over the top of the limb; still open, on the dark webbing lying
    // on the blanket just short of the (teal) pull tab, where a teal ring stands out
    strapMarkAt(i) {
      const s = this.st.straps[i], sm = this.straps[i], wr = s.k >= 0.999;
      const pa = sm.path ? sm.path[Math.floor(sm.SM * (wr ? 0.5 : 0.72))] : null;
      return pa ? this.sw(s.x, pa[1] + (wr ? 0.012 : 0.004), pa[0]) : sm.pull.getWorldPosition(V3()).add(V3(0, 0.01, 0));
    }
    strapNear(px) {
      let best = -1, bd = 1e9;
      this.straps.forEach((sm, i) => {
        if (!sm.path) return;
        const s = this.st.straps[i];
        let prev = null;
        sm.path.forEach((p, j) => {
          if (j % 2) return;
          const q = this.toPx(this.sw(s.x, p[1], p[0]));
          if (prev) { const d = segDist(px, prev, q); if (d < bd) { bd = d; best = i; } }
          prev = q;
        });
        const pt = this.toPx(sm.pull.getWorldPosition(V3()));
        const dd = Math.hypot(pt.x - px.x, pt.y - px.y);
        if (dd < bd) { bd = dd; best = i; }
      });
      return { i: best, d: bd };
    }

    /* ─────────────── input ─────────────── */
    down(e) {
      if (!this.ready || e.button !== 0 || this.st.finished || this.app.S !== this.st) return;
      this.lmb = true;
      const n = this.simMs();
      if (this.step === 1) this.layDown();
      else if (this.step === 2) this.padDown();
      else if (this.step === 3) this.shapeDown(n);
      else if (this.step === 4) this.strapDown(n);
      else if (this.step === 5) this.cmsDown(n);
    }
    up(e) {
      if (e.button !== 0) return;
      const was = this.lmb;
      this.lmb = false;
      if (!was || !this.ready || this.st.finished) return;
      const n = this.simMs();
      if (this.step === 1) this.layUp();
      else if (this.step === 3) this.shapeUp(n);
      else if (this.step === 4) this.strapUp(n);
      else if (this.step === 5) this.cmsUp(n);
    }
    pointer() { if (this.step === 1 && this.sp.drag && this.lmb) this.dragTo(); }
    keySet() {
      if (!this.ready || this.st.finished || this.step !== 1 || this.sp.locked) return;
      if (this.sp.ok) this.lockSplint();
      else { this.pp.flash('warn', T('not_aligned', 'Both ends must sit past their joints first.'), 2000); NZA.audio.click(260); }
    }
    keyReset() {
      const sp = this.sp;
      if (!this.ready || this.step !== 1 || sp.locked) return;
      sp.x = sp.x0; sp.z = sp.z0; sp.under = false; sp.drop = 0; sp.drag = null; sp.anim = null; sp.hold = 0; sp.moved = false;
      this.st.resets += 1;
      NZA.audio.noise(160, { vol: 0.05, lp: 1400, hp: 300 });
      this.frameStep(1);
      this.pp.set({ text: this.text() });
    }

    /* ═════════════ 1. LAY THE SPLINT ═════════════ */
    layDown() {
      const sp = this.sp, o = this.so;
      if (sp.locked) return;
      const yMid = this.splint.position.y + o.yF + o.depth * 0.5;
      const hit = this.hitY(yMid);
      if (!hit) return;
      const lx = hit.x - sp.x, lz = hit.z - sp.z, hwOut = o.hw0 * (1 + o.flare) + o.th;
      if (Math.abs(lx) <= o.L / 2 + 0.03 && Math.abs(lz) <= hwOut + 0.04) {
        sp.drag = { off: [sp.x - hit.x, sp.z - hit.z], y: yMid, zt: sp.z };
        sp.moved = true;
        NZA.audio.click(560);
      } else this.flashOnce('warn', T('g3_f_grab', 'Grab the splint itself to move it.'), 1600);
    }
    dragTo() {
      const sp = this.sp, o = this.so, dr = sp.drag;
      if (!dr) return;
      const hit = this.hitY(dr.y);
      if (!hit) return;
      let x = hit.x + dr.off[0];
      const zt = hit.z + dr.off[1];
      if (this.shift) x = sp.x + (x - sp.x) * this.tune.fine;
      sp.x = clamp(x, this.xT - 0.32, this.xT + 0.32);
      dr.zt = zt;
      const snap = o.hw0 * 0.9 + this.R * 0.6;
      if (!sp.under && Math.abs(zt) < snap) this.slideUnder(true);
      else if (sp.under && zt > snap * 2.2) this.slideUnder(false);
      if (!sp.under && !sp.anim) sp.z = clamp(zt, snap * 0.95, sp.z0 + 0.12);
    }
    slideUnder(on) {
      const sp = this.sp;
      if (sp.under === on) return;
      sp.under = on;
      sp.anim = { t: 0, z0: sp.z, z1: on ? 0 : Math.max(sp.z0 * 0.85, this.so.hw0 * 2), d0: sp.drop, d1: on ? 1 : 0 };
      NZA.audio.noise(on ? 220 : 160, { vol: 0.07, lp: 900, hp: 120, attack: 0.03, release: 0.3 });
      if (on) this.flashOnce('ok', T('g3_f_under', 'Under the limb. Now line the ends up with the outline.'), 1800);
      if (!sp.drag) this.frameStep(1); else sp.reframe = true;
      this.pp.set({ text: this.text() });
    }
    layUp() {
      const sp = this.sp;
      if (!sp.drag) return;
      this.dragTo();
      sp.drag = null;
      if (sp.reframe) { sp.reframe = false; this.frameStep(1); }
      if (!sp.under) this.flashOnce('warn', T('g3_f_under_first', 'Slide it all the way under the limb.'), 1800);
      else if (!sp.ok) this.flashOnce('warn', T('g3_f_far', 'Not on the outline yet: both ends must reach past the joints.'), 1800);
    }
    tickLay(dt) {
      const sp = this.sp, tol = this.tune.tolerance;
      if (sp.locked) {
        if (sp.anim) { sp.anim.t += dt / 0.3; sp.x = lerp(sp.anim.x0, this.xT, smooth(0, 1, sp.anim.t)); if (sp.anim.t >= 1) sp.anim = null; this.placeSplint(1); }
        return;
      }
      if (sp.drag && this.lmb) this.dragTo();
      if (sp.under && !sp.drag && (this.held.has('l') || this.held.has('r'))) {
        const v = this.tune.nudgeSpeed * (this.shift ? this.tune.fine : 1) * dt;
        sp.x = clamp(sp.x + (this.held.has('r') ? v : 0) - (this.held.has('l') ? v : 0), this.xT - 0.32, this.xT + 0.32);
        sp.moved = true;
      }
      if (sp.anim) {
        sp.anim.t += dt / 0.38;
        const e = smooth(0, 1, sp.anim.t);
        sp.z = lerp(sp.anim.z0, sp.anim.z1, e); sp.drop = lerp(sp.anim.d0, sp.anim.d1, e);
        if (sp.anim.t >= 1) sp.anim = null;
      }
      this.placeSplint(sp.drop);
      const err = Math.abs(sp.x - this.xT);
      const ok = sp.under && !sp.anim && err <= tol;
      if (ok && !sp.ok) NZA.audio.tone(1250, 60, { vol: 0.06, type: 'triangle' });
      sp.ok = ok;
      if (ok && !sp.drag && sp.moved && !this.held.size) sp.hold += dt; else sp.hold = 0;
      if (sp.hold >= this.tune.lockHold) this.lockSplint();
    }
    lockSplint() {
      const sp = this.sp, st = this.st, tol = this.tune.tolerance;
      if (sp.locked) return;
      const e = Math.abs(sp.x - this.xT);
      st.s1 = Math.round(clamp(100 - (e / tol) * 22 - Math.max(0, st.resets - 1) * 4, 35, 100));
      sp.locked = true; sp.drag = null; sp.anim = { t: 0, x0: sp.x };
      this.placed = true;
      this.ghostG.visible = false;
      this.refillTrough();
      NZA.audio.noise(140, { vol: 0.12, lp: 420, hp: 40, attack: 0.02, release: 0.5 });
      NZA.audio.success();
      this.pp.flash('ok', T('set_ok', 'Splint set - it holds the joint above and below the break.'), 2400);
      const S0 = st;
      setTimeout(() => { if (this.alive && this.st === S0 && this.step === 1) { this.enter(2); this.refreshTools(); } }, 800);
    }

    /* ═════════════ 2. PAD THE BONY POINTS ═════════════ */
    padDown() {
      const st = this.st, px = this.ptrPx(), U = this.pxScale();
      let best = -1, bd = 95 * U;
      st.sites.forEach((s, i) => { if (s.padded) return; const q = this.toPx(this.sitePos(i)); const dd = Math.hypot(q.x - px.x, q.y - px.y); if (dd < bd) { bd = dd; best = i; } });
      if (best < 0) { this.flashOnce('warn', T('g3_f_pad_where', 'Click one of the marked bony points.'), 1600); return; }
      this.padSite(best);
    }
    padSite(i, instant) {
      const st = this.st, s = st.sites[i], J = this.joints();
      if (s.padded) return;
      s.padded = true; s.pop = 1; s.k = instant ? 1 : 0;
      this.refillTrough();
      NZA.audio.noise(180, { vol: 0.07, lp: 700, hp: 120, attack: 0.1 });
      if (!instant) this.pp.flash('ok', T('padded', 'Padded at the %s.', (i === 0 ? J.prox : J.dist).toLowerCase()), 1500);
      this.refreshTools();
      if (st.sites.every(x => x.padded) && !instant) {
        const S0 = st;
        setTimeout(() => { if (this.alive && this.st === S0 && this.step === 2) this.enter(3); }, 700);
      }
    }
    tickPad(dt) {
      const st = this.st;
      st.sites.forEach((s, i) => {
        if (s.padded && (s.k || 0) < 1) s.k = Math.min(1, (s.k || 0) + dt / 0.3);
        if (s.pop > 0) s.pop = Math.max(0, s.pop - dt * 2.2);
        this.placePads(i, s.padded ? smooth(0, 1, s.k || 0) : 0);
      });
    }

    /* ═════════════ 3. SHAPE ═════════════ */
    // the wall's give while pressed: 1 / shapeSeconds per second, but slow through the teal band so the
    // window to let go is at least SHAPE_ZONE_S long (forgiving at a low frame rate); memoryless, so a
    // Shift change re-bases it at the value it has now
    pressF(n) {
      const p = this.press;
      if (!p) return 0;
      if (this.freeze) n = p.t0;
      const ss = Math.max(0.3, +this.tune.shapeSeconds || 1.15), z0 = this.tune.shapeZone[0], z1 = this.tune.shapeZone[1];
      const slow = (z1 - z0) / Math.max((z1 - z0) * ss, SHAPE_ZONE_S);
      let f = p.f0, t = Math.max(0, (n - p.t0) / 1000) * p.rate;
      if (f < z0) { const need = (z0 - f) * ss; if (t <= need) return f + t / ss; t -= need; f = z0; }
      if (f < z1) { const need = (z1 - f) / slow; if (t <= need) return f + t * slow; t -= need; f = z1; }
      return f + t / ss;
    }
    nearestPoint(maxPx) {
      const px = this.ptrPx(), U = this.pxScale();
      let best = -1, bd = maxPx * U;
      this.st.points.forEach((p, i) => { if (p.done) return; const q = this.toPx(this.pointPos(i)); const dd = Math.hypot(q.x - px.x, q.y - px.y); if (dd < bd) { bd = dd; best = i; } });
      return best;
    }
    shapeDown(n) {
      const i = this.nearestPoint(85);
      if (i < 0) {
        if (this.st.points.every(p => p.done)) return;
        this.flashOnce('warn', T('g3_f_shape_where', 'Press on one of the marked points along the wall.'), 1600);
        return;
      }
      const pt = this.st.points[i];
      this.press = { i, f0: Math.min(1.04, pt.f + this.tune.shapeClick), t0: n, rate: this.shift ? 0.45 : 1 };
      pt.f = this.press.f0;
      NZA.audio.noise(120, { vol: 0.05, lp: 900, hp: 200 });
      this.checkTight(n);
    }
    checkTight(n) {
      const p = this.press;
      if (!p) return;
      const pt = this.st.points[p.i], f = this.pressF(n);
      pt.f = Math.min(f, 1.08);
      if (f > this.tune.shapeZone[1] && !pt.tight) {
        pt.tight = true; pt.done = true; pt.pop = 1; pt.f = Math.min(f, 1.06);
        this.press = null;
        NZA.audio.click(240);
        this.pp.flash('bad', T('pressure_point', 'Too much: that leaves a pressure point under the splint.'), 2400);
        this.refillTrough();
        this.checkShapeDone();
      }
    }
    shapeUp(n) {
      const p = this.press;
      if (!p) return;
      this.checkTight(n);
      if (!this.press) return;
      const pt = this.st.points[p.i];
      pt.f = Math.min(this.pressF(n), 1.08);
      this.press = null;
      if (pt.f >= this.tune.shapeZone[0]) { pt.done = true; pt.pop = 1; NZA.audio.click(880); }
      else this.flashOnce('warn', T('g3_f_shape_short', 'Keep pressing until the ring turns teal, then let go.'), 1700);
      this.refillTrough();
      this.checkShapeDone();
    }
    checkShapeDone() {
      const st = this.st;
      if (st.shapeDone || !st.points.every(p => p.done)) return;
      st.shapeDone = true;
      st.s2 = this.shapeScore();
      NZA.audio.success();
      this.pp.flash('ok', T('shape_ok', 'Splint shaped to the limb.'), 2000);
      const S0 = st;
      setTimeout(() => { if (this.alive && this.st === S0 && this.step === 3) { this.enter(4); this.refreshTools(); } }, 800);
    }
    // the shaping score from how each point was pressed (a pressure point scores low)
    shapeScore() {
      const [z0, z1] = this.tune.shapeZone, pts = this.st.points;
      const q = pts.map(p => (p.tight ? 52 : clamp(100 - Math.abs(p.f - (z0 + z1) / 2) * 140, 60, 100)));
      return Math.round(q.reduce((a, b) => a + b, 0) / q.length);
    }
    tickShape() {
      const n = this.simMs();
      if (this.press && !this.freeze) { this.checkTight(n); this.refillTrough(); }
      this.st.points.forEach(p => { if (p.pop > 0) p.pop = Math.max(0, p.pop - 0.04); });
    }

    /* ═════════════ 4. STRAPS ═════════════ */
    // tension while the strap is pulled (s since it came round): slow through the teal band
    tensionAt(sec) {
      const P = Math.max(0.6, +this.tune.strapPeriod || 1.7), z = this.tune.strapZone, tt = this.tune.strapTight;
      const K = [[0, 0], [0.5 * P, z[0]], [1.1 * P, z[1]], [1.32 * P, tt], [1.6 * P, 1]];
      if (sec <= 0) return 0;
      for (let i = 1; i < K.length; i++) if (sec <= K[i][0]) return lerp(K[i - 1][1], K[i][1], (sec - K[i - 1][0]) / (K[i][0] - K[i - 1][0]));
      return 1;
    }
    strapDown(n) {
      const st = this.st, r = this.strapNear(this.ptrPx());
      if (r.i < 0 || r.d > 48 * this.pxScale()) { this.flashOnce('warn', T('g3_f_strap_where', 'Hold on one of the straps.'), 1600); return; }
      const s = st.straps[r.i];
      if (st.cms.state === 'ok') return;
      if (s.state === 'locked' && !s.tight && this.badStrap() >= 0) { this.flashOnce('warn', T('g3_f_strap_other', 'That one is fine: loosen the strap marked red.'), 1800); return; }
      if (s.state === 'open') { s.state = 'wrapping'; NZA.audio.noise(340, { vol: 0.08, lp: 5200, hp: 1400, attack: 0.02, release: 0.4 }); }
      else {
        // loosen it and pull again
        if (s.state === 'locked') { s.tight = false; s.loose = false; NZA.audio.noise(200, { vol: 0.07, lp: 4200, hp: 1200, attack: 0.02, release: 0.3 }); }
        s.state = 'pulling'; s.tension = 0;
      }
      this.pull = { i: r.i, t0: n + (s.state === 'wrapping' ? (1 - s.k) * WRAP_T * 1000 : 0) };
      if (st.cms.state === 'bad' || st.cms.state === 'ready') st.cms.state = 'hidden';
    }
    strapUp(n) {
      const p = this.pull;
      if (!p) return;
      this.pull = null;
      const st = this.st, s = st.straps[p.i];
      if (s.state === 'wrapping' || (n - p.t0) < 60) {
        if (s.state !== 'wrapping') s.state = 'wrapped';
        s.tension = 0;
        this.flashOnce('warn', T('g3_f_strap_hold', 'Keep holding: it pulls tight once it is round the limb.'), 1800);
        return;
      }
      s.tension = this.tensionAt((n - p.t0) / 1000);
      this.lockStrap(p.i);
    }
    lockStrap(i) {
      const st = this.st, s = st.straps[i];
      s.state = 'locked'; s.locks += 1;
      this.strapGrade(s);
      if (s.tight) st.tightEver += 1;
      NZA.audio.click(s.tight ? 300 : s.loose ? 520 : 940);
      this.pp.flash(s.tight ? 'bad' : s.loose ? 'warn' : 'ok', s.tight ? T('strap_tight', 'Strap %s is very tight.', i + 1) : s.loose ? T('strap_loose', 'Strap %s is loose - the splint can slip.', i + 1) : T('strap_ok', 'Strap %s secured.', i + 1), 1800);
      this.refreshTools();
      if (st.straps.every(x => x.state === 'locked')) {
        st.cms.state = 'ready';
        const S0 = st;
        setTimeout(() => { if (this.alive && this.st === S0 && this.step === 4 && st.straps.every(x => x.state === 'locked')) { this.enter(5); this.refreshTools(); } }, 800);
      } else this.pp.set({ title: this.title(), text: this.text() });
    }
    // a cinched strap's grade from its tension: quality, too tight (cuts the circulation off), loose
    strapGrade(s) {
      const z = this.tune.strapZone, tn = s.tension;
      s.quality = tn > this.tune.strapTight ? 30 : tn < z[0] ? clamp(78 - (z[0] - tn) * 160, 30, 78) : clamp(100 - Math.abs(tn - (z[0] + z[1]) / 2) * 90, 80, 100);
      s.tight = tn > this.tune.strapTight;
      s.loose = tn < z[0];
    }
    tickStrap(dt) {
      const st = this.st, n = this.simMs();
      st.straps.forEach((s, i) => {
        if (s.state === 'wrapping') {
          s.k = Math.min(1, s.k + dt / WRAP_T);
          if (s.k >= 1) {
            NZA.audio.noise(90, { vol: 0.05, lp: 3000, hp: 800 });
            s.state = this.pull && this.pull.i === i && this.lmb ? 'pulling' : 'wrapped';
          }
        }
        if (s.state === 'pulling' && this.pull && this.pull.i === i && !this.freeze) s.tension = this.tensionAt((n - this.pull.t0) / 1000);
      });
    }

    /* ═════════════ 5. DISTAL CHECK (CMS) ═════════════ */
    nailNear(maxPx) {
      const px = this.ptrPx(), U = this.pxScale();
      let best = null, bd = maxPx * U;
      this.distal.nails.forEach(nl => { const q = this.toPx(nl.nail.getWorldPosition(V3())); const dd = Math.hypot(q.x - px.x, q.y - px.y); if (dd < bd) { bd = dd; best = nl; } });
      return best;
    }
    cmsDown(n) {
      const c = this.st.cms;
      if (c.state !== 'ready' && c.state !== 'bad') return;
      const nl = this.nailNear(80);
      if (!nl) { this.flashOnce('warn', T('g3_f_nail_where', 'Press on one of the nails.'), 1600); return; }
      this.blanch = { nail: nl, t0: n };
      c.state = 'blanch';
    }
    cmsUp(n) {
      const b = this.blanch, c = this.st.cms;
      if (!b || c.state !== 'blanch') return;
      this.blanch = null;
      const f = (n - b.t0) / 1000 / BLANCH;
      if (f < 1) { c.state = 'ready'; this.flashOnce('warn', T('g3_f_nail_short', 'Press a little longer, until the nail goes white.'), 1700); return; }
      this.cmsCheck(b.nail, n);
    }
    cmsCheck(nail, n) {
      const st = this.st, c = st.cms, d = this.d;
      const tight = st.straps.some(s => s.tight);
      const pulse = d.pulse || 'present', leg = this.kind === 'leg', resp = d.responsive !== false;
      const refill = tight ? 3.6 : +d.refill || (pulse === 'present' ? 1.4 : 3.2);
      const rows = [];
      if (tight) rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_tight', 'Faint pulse · refill %s s', refill.toFixed(1)), tone: 'red' });
      else if (pulse === 'absent') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_absent', 'No pulse below the tourniquet'), tone: 'amber' });
      else if (pulse === 'weak') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_weak', 'Weak, thready pulse - in shock'), tone: 'amber' });
      else rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_ok', 'Pulse present · refill %s s', refill.toFixed(1)), tone: 'teal' });
      if (!resp) rows.push({ k: 'M', label: T('motor', 'Movement'), value: T('m_unresp', 'Not testable - unresponsive'), tone: 'amber' });
      else rows.push({ k: 'M', label: T('motor', 'Movement'), value: tight ? T('m_tight', 'Barely moves') : (leg ? T('m_leg', 'Wiggles the toes') : T('m_arm', 'Moves the fingers')), tone: tight ? 'amber' : 'teal' });
      if (!resp) rows.push({ k: 'S', label: T('sens', 'Feeling'), value: T('s_unresp', 'Not testable - unresponsive'), tone: 'amber' });
      else rows.push({ k: 'S', label: T('sens', 'Feeling'), value: tight ? T('s_tight', 'Pins and needles') : T('s_ok', 'Feels a light touch'), tone: tight ? 'red' : 'teal' });
      const shorts = [
        tight ? T('g3_c_faint', 'Faint') : pulse === 'absent' ? T('g3_c_absent', 'Absent') : pulse === 'weak' ? T('g3_c_weak', 'Weak') : T('g3_c_ok', 'Pink, %s s', refill.toFixed(1)),
        !resp ? T('g3_untestable', 'Not testable') : tight ? T('g3_m_tight', 'Barely') : T('g3_m_ok', 'Moves'),
        !resp ? T('g3_untestable', 'Not testable') : tight ? T('g3_s_tight', 'Tingling') : T('g3_s_ok', 'Feels touch'),
      ];
      rows.forEach((r, i) => { r.short = shorts[i]; });
      c.rows = rows; c.tight = tight; c.refill = refill; c.checks += 1; c.shown = 0;
      c.state = 'checking'; c.t0 = n; c.nail = nail;
      NZA.audio.click(700);
    }
    tickCms(dt) {
      const st = this.st, c = st.cms, d = this.d, n = this.simMs();
      const tight = st.straps.some(s => s.tight);
      const dusk = tight ? 0.65 : d.pulse === 'absent' ? 0.5 : d.pulse === 'weak' ? 0.25 : 0;
      // nail colours: the pressed one blanches, then refills
      this.distal.nails.forEach(nl => {
        let perf = 1;
        if (this.blanch && this.blanch.nail === nl && c.state === 'blanch') perf = 1 - clamp((n - this.blanch.t0) / 1000 / BLANCH, 0, 1);
        else if (c.state === 'checking' && c.nail === nl) perf = clamp((n - c.t0) / 1000 / Math.max(0.3, c.refill), 0, 1);
        if (this.freezeBlanch !== undefined && (c.nail === nl || (this.blanch && this.blanch.nail === nl))) perf = this.freezeBlanch;
        const key = `${perf.toFixed(3)}|${dusk}`;
        if (nl.key !== key) { nl.key = key; nl.mat.color.copy(this.nailColor(perf, dusk)); }
      });
      if (c.state !== 'checking' || this.freeze) return;
      const el2 = (n - c.t0) / 1000, tR = c.refill, tM = tR + 1.5, tS = tM + 1.5;
      const shown = el2 >= tS ? 3 : el2 >= tM ? 2 : el2 >= tR ? 1 : 0;
      if (shown !== c.shown) {
        c.shown = shown;
        NZA.audio.tick();
        if ((shown === 1 || shown === 2) && d.responsive !== false && (!NZA.inGame || d.speech !== false)) {
          const leg = this.kind === 'leg';
          const line = shown === 1 ? (c.tight ? T('say_m_tight', 'I... can barely move them.') : (leg ? T('say_m_leg', 'Yeah, I can move my toes.') : T('say_m_arm', 'Yeah, my fingers move.')))
            : (c.tight ? T('say_s_tight', 'It\'s all pins and needles down there.') : T('say_s_ok', 'I can feel that, yes.'));
          NZA.speech({ name: d.name || T('patient', 'Patient'), text: line, ms: 2200, role: T('patient', 'Patient') });
        }
      }
      // the toes / fingers move while the movement row is checked
      const wig = d.responsive === false ? 0 : (shown === 1 ? 1 : 0) * (c.tight ? 0.3 : 1);
      this.distal.digits.forEach((dg, i) => {
        const a = wig * dg.wig * Math.sin((el2 - tR) * 7 + i * 0.9) * smooth(0, 0.3, el2 - tR) * (1 - smooth(1.2, 1.5, el2 - tR));
        dg.group.setRotationFromAxisAngle(dg.axis, a);
      });
      if (el2 >= tS + 0.4) {
        if (c.tight) {
          c.state = 'bad'; c.fixed = true;
          NZA.audio.fail();
          this.pp.flash('bad', T('g3_cms_fail', 'No good pulse below the splint: a strap is too tight. Hold on the strap marked red to loosen it and pull it again, then check again.'), 5200);
          const S0 = st;
          setTimeout(() => { if (this.alive && this.st === S0 && c.state === 'bad') { this.enter(4); this.refreshTools(); } }, 1600);
        } else {
          c.state = 'ok';
          this.finish();
        }
      }
    }

    /* ─────────────── finish / abort ─────────────── */
    finish() {
      const st = this.st;
      if (st.finished) return;
      st.finished = true;
      this.pp.set({ pause: false });   // nothing left to step away from
      const q = st.straps.map(s => s.quality), strapAvg = q.reduce((a, b) => a + b, 0) / q.length;
      const checksPenalty = Math.max(0, st.cms.checks - (st.cms.fixed ? 2 : 1)) * 4;
      st.s3 = Math.round(clamp(strapAvg + (st.cms.fixed ? 4 : 0) - checksPenalty, 25, 100));
      const score = Math.round(clamp(st.s1 * 0.4 + st.s2 * 0.3 + st.s3 * 0.3, 0, 100));
      const result = {
        score, align: st.s1, mould: st.s2, straps: st.s3, cms: 'ok', checks: st.cms.checks,
        pressure: st.points.filter(p => p.tight).length, padded: st.sites.filter(s => s.padded).length,
        tight: st.tightEver, loose: st.straps.filter(s => s.loose).length, resets: st.resets,
        time: Math.round((performance.now() - st.t0) / 100) / 10,
      };
      st.result = result;
      NZA.audio.success();
      this.useHand(null);
      this.cursor(null, '');
      this.stageCursor('');
      this.frameStep(4, !!this.freeze || this.jumping);
      this.pp.set({ title: T('securing', 'Recording the splint…'), titleTone: '', text: T('securing_text', 'Distal check intact. Writing it on the patient record.'), tools: this.toolsFor(), wide: { label: T('score', 'Score'), value: score, unit: '', tone: 'teal', meter: { value: score / 100 } } });
      const app = this.app;
      NZA.post(`${APP}:finish`, result).then(r => {
        if (!NZA.inGame && r && r.outcome && this.alive && app.S === st) app.showResult(r.outcome);
      });
    }
    abort() {
      if (this.st.finished) return;
      NZA.post(`${APP}:abort`, {});
      if (!NZA.inGame) { NZA.toast({ title: T('title', 'Splint'), message: T('aborted', 'Splinting stopped'), type: 'error' }); NZA.close(APP); }
    }

    /* ─────────────── per frame ─────────────── */
    frame(dt, render) {
      if (!this.alive || !this.S) return;
      this.applyCam(dt);
      this.t += dt;
      if (this.step === 1) this.tickLay(dt);
      if (this.step >= 2) this.tickPad(dt);
      if (this.step === 3) this.tickShape(dt);
      if (this.step === 4 || (this.st.cms.state === 'bad' && this.step === 5)) this.tickStrap(dt);
      if (this.step === 5) this.tickCms(dt);
      if (!render) return;
      this.visuals();
      this.drawCursor();
      const n = performance.now();
      if (n - this.uiAt > 120) { this.uiAt = n; this.panel(); }
    }
    visuals() {
      const S = this.S, st = this.st, step = this.step, n = this.freeze ? this.freezeAt : this.simMs(), sp = this.sp;
      this.marks.forEach(m => { m.userData.used = false; });
      this.updateStraps();
      const px = this.ptrPx(), U = this.pxScale(), pulse = 0.72 + 0.28 * Math.sin(this.t * 5);
      let cls = '';
      if (st.finished) { this.useHand(null); this.padTool.visible = false; }
      else if (step === 1) {
        this.useHand(null);
        this.ghostG.visible = !sp.locked;
        this.M.ghost.opacity = sp.ok ? 0.3 + 0.1 * Math.sin(this.t * 6) : 0.16;
        this.M.ghost.color.setHex(0x2fe0d0);
        this.outlineMat.opacity = sp.ok ? 1 : 0.6 + 0.35 * Math.sin(this.t * 4);
        this.outlineMat.color.setHex(sp.ok ? 0x7dfff1 : 0x2fe0d0);
        cls = sp.drag ? 'grabbing' : 'grab';
        if (sp.locked) this.cursor(null, '');
        else if (sp.drag) this.cursor(sp.ok ? clamp(sp.hold / this.tune.lockHold, 0, 1) : null, sp.under ? (sp.ok ? T('g3_cur_seated', 'On the outline: let go') : T('g3_cur_slide', 'Slide along')) : T('g3_cur_under', 'Under the limb'), sp.ok ? 'teal' : '');
        else if (sp.ok) this.cursor(clamp(sp.hold / this.tune.lockHold, 0, 1), T('g3_cur_hold', 'Hold still…'), 'teal');
        else this.cursor(null, '');
      } else if (step === 2) {
        this.useHand(null);
        let near = -1;
        st.sites.forEach((s, i) => {
          const p = this.sitePos(i);
          if (s.padded) this.mark(`site${i}`, p, 'check', 0x2fe0d0, 26, 0.9);
          else {
            this.mark(`site${i}`, p, 'ring', 0x2fe0d0, 46 * pulse + 6, 0.95);
            const q = this.toPx(p);
            if (Math.hypot(q.x - px.x, q.y - px.y) < 95 * U) near = i;
          }
        });
        // the padding roll in your hand follows the cursor
        const h = this.hitLimb(), P = h ? h.point : this.hitY(this.yb + this.R);
        if (P && !st.sites.every(s => s.padded)) {
          this.padTool.visible = true;
          this.padTool.position.copy(P).add(V3(0, 0.022, 0.004));
          this.padTool.rotation.set(0.1, 0.3, 0.06);
          cls = 'hide';
        } else this.padTool.visible = false;
        this.cursor(null, near >= 0 ? T('g3_cur_pad', 'Click: pad it') : '', 'teal');
      } else if (step === 3) {
        this.padTool.visible = false;
        st.points.forEach((p, i) => {
          const pos = this.pointPos(i);
          if (p.tight) this.mark(`pt${i}`, pos, 'check', 0xf3c35a, 24, 0.95);
          else if (p.done) this.mark(`pt${i}`, pos, 'check', 0x2fe0d0, 22 * (1 + 0.3 * p.pop), 0.95);
          else if (!this.press || this.press.i !== i) this.mark(`pt${i}`, pos, 'ring', 0x2fe0d0, 40 * pulse + 4, 0.9);
        });
        // the hand: on the wall at the point you press (or near), else over the cursor
        const i = this.press ? this.press.i : this.nearestPoint(85);
        const o = this.so;
        if (i >= 0) {
          const x = st.points[i].x, pr = this.profile(x, false), hwTop = pr.hw * (1 + pr.flare);
          const P = this.sw(x, pr.yT - 0.014, hwTop + o.th + 0.0005);
          const nrm = V3(0, 0.42, 0.91).normalize();
          // palm on the outside of the wall, fingers up toward the rim, the forearm coming in from below you
          this.poseHand(this.hands.press, P, nrm, V3(-0.25, -1, 0.3), 1.0, this.press ? 0.0012 : -0.006);
          this.useHand('press');
          cls = 'hide';
        } else {
          const P = this.hitY(this.yb + this.R * 2.1);
          if (P) { this.poseHand(this.hands.press, P, V3(0, 1, 0), V3(-0.2, 0, 1), 1.1, -0.004); this.useHand('press'); cls = 'hide'; } else this.useHand(null);
        }
        if (this.press) {
          const f = this.pressF(n), z = this.tune.shapeZone, inZ = f >= z[0] && f <= z[1];
          this.cursor(clamp(f / 1.1, 0, 1), inZ ? T('cap_release', 'Let go now') : f > z[1] ? T('g3_cur_tight', 'Too much') : T('g3_cur_pressing', 'Pressing…'), inZ ? 'teal' : f > z[1] ? 'red' : 'white', [z[0] / 1.1, Math.min(1, z[1] / 1.1)]);
        } else this.cursor(null, i >= 0 ? T('g3_cur_press', 'Hold: press') : '', '');
      } else if (step === 4) {
        this.useHand(null);
        const bad = this.badStrap();
        st.straps.forEach((s, i) => {
          const at = this.strapMarkAt(i);
          if (s.state === 'locked') this.mark(`st${i}`, at, 'check', s.tight ? 0xff6b70 : s.loose ? 0xf3c35a : 0x2fe0d0, s.tight ? 30 * pulse + 4 : 22, 0.95);
          else if (!this.pull || this.pull.i !== i) this.mark(`st${i}`, at, 'ring', bad >= 0 ? 0x8aa : 0x2fe0d0, 48 * pulse + 8, bad >= 0 ? 0.4 : 0.95);
          if (s.tight && s.state === 'locked') this.mark(`stb${i}`, at, 'ring', 0xff6b70, 52 * pulse + 6, 0.9);
        });
        const r = this.strapNear(px);
        const over = r.i >= 0 && r.d < 48 * U;
        cls = this.pull ? 'grabbing' : over ? 'point' : '';
        if (this.pull) {
          const s = st.straps[this.pull.i];
          if (s.state === 'wrapping') this.cursor(null, T('g3_cur_wrap', 'Wrapping…'), 'teal');
          else {
            const z = this.tune.strapZone, tn = s.tension, inZ = tn >= z[0] && tn <= z[1];
            this.cursor(tn, inZ ? T('cap_cinch', 'Cinch now') : tn > this.tune.strapTight ? T('cap_tight', 'Too tight') : tn > z[1] ? T('g3_cur_firm', 'Very firm') : T('g3_cur_pulling', 'Pulling…'), inZ ? 'teal' : tn > this.tune.strapTight ? 'red' : tn > z[1] ? 'amber' : 'white', z);
          }
        } else this.cursor(null, over ? T('g3_cur_strap', 'Hold: wrap & pull') : '', '');
      } else if (step === 5) {
        const c = st.cms, nl = this.nailNear(80);
        const target = this.blanch ? this.blanch.nail : c.state === 'checking' ? c.nail : (nl || null);
        if (c.state === 'ready' || c.state === 'bad') this.mark('nail', this.checkNail.nail.getWorldPosition(V3()), 'ring', 0x2fe0d0, 34 * pulse + 6, 0.9);
        if (target && (c.state === 'blanch' || c.state === 'ready' || c.state === 'bad')) {
          const P = target.nail.getWorldPosition(V3()), nrm = V3(0, 1, 0).applyQuaternion(target.nail.getWorldQuaternion(new THREE.Quaternion())).normalize();
          const cam = S.camera.position, toCam = cam.clone().sub(P).normalize();
          const right = V3(1, 0, 0).applyQuaternion(S.camera.quaternion), upv = V3(0, 1, 0).applyQuaternion(S.camera.quaternion);
          // the forearm comes in from beyond the toe tips (toes up: it would hide the foot from the knee side),
          // or from the lower right for the fingers
          const leg = this.kind === 'leg';
          const dir = leg ? V3(0.2, 1, 0) : toCam.multiplyScalar(0.15).addScaledVector(right, 0.85).addScaledVector(upv, -0.35);
          const b = this.blanch ? clamp((n - this.blanch.t0) / 1000 / BLANCH, 0, 1) : 0;
          this.poseHand(this.hands.point, P.addScaledVector(nrm, 0.0012), nrm, dir, leg ? 1.2 : 0.95, this.blanch ? 0.0006 + 0.0012 * b : -0.004);
          this.useHand('point');
          cls = 'hide';
        } else this.useHand(null);
        if (c.state === 'blanch' && this.blanch) {
          const b = clamp((n - this.blanch.t0) / 1000 / BLANCH, 0, 1);
          this.cursor(b, b >= 1 ? T('g3_cur_white', 'White: let go') : T('g3_cur_blanch', 'Pressing…'), b >= 1 ? 'teal' : 'white');
        } else if (c.state === 'checking') this.cursor(null, '');
        else this.cursor(null, nl ? T('g3_cur_nail', 'Hold: press the nail') : '', '');
      }
      this.stageCursor(cls);
      this.marks.forEach(m => { if (!m.userData.used) m.visible = false; });
    }
    drawCursor() {
      const c = this.cur, S = this.S;
      const on = !this.st.finished && (c.p !== null || !!c.text);
      this.curEl.classList.toggle('on', on);
      if (!on) return;
      if (!this.zoom) this.zoom = parseFloat(getComputedStyle(this.app.el).zoom) || 1;
      const x = S.pointer.x * window.innerWidth / this.zoom, y = S.pointer.y * window.innerHeight / this.zoom;
      this.curEl.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`;
      const cls = `sg3-cur on ${c.p === null ? 'noring' : ''} ${c.tone}`;
      if (this.curEl.className !== cls) this.curEl.className = cls;
      if (c.p !== null) {
        const C = 119.4;
        this.curFg.setAttribute('stroke-dasharray', `${(clamp(c.p, 0, 1) * C).toFixed(1)} 120`);
        if (c.zone) { this.curZn.setAttribute('stroke-dasharray', `${((c.zone[1] - c.zone[0]) * C).toFixed(1)} 120`); this.curZn.setAttribute('stroke-dashoffset', `${(-c.zone[0] * C).toFixed(1)}`); }
        else this.curZn.setAttribute('stroke-dasharray', '0 120');
      }
      if (this.curTx.textContent !== c.text) this.curTx.textContent = c.text;
    }

    /* ─────────────── HUD readouts ─────────────── */
    panel(force) {
      const st = this.st, t = this.tune, J = this.joints(), n = this.freeze ? this.freezeAt : this.simMs();
      if (st.finished) return;
      let wide, stats;
      if (this.step === 1) {
        const sp = this.sp, err = Math.abs(sp.x - this.xT), tol = t.tolerance;
        const fit = sp.under ? Math.round(clamp(100 - (Math.min(err, tol * 6) / (tol * 6)) * 100, 0, 100)) : 0;
        const ok = sp.ok;
        wide = { label: T('fit', 'Fit'), value: fit, unit: '%', tone: ok ? 'teal' : '', meter: { value: fit / 100, zone: [0.82, 1], tone: ok ? '' : 'white' },
          caption: !sp.under ? T('g3_cap_under', 'Slide it under the limb') : ok ? T('cap_hold', 'Hold still to set') : T('cap_fit', 'Reach past both joints'), captionTone: ok ? 'teal' : '' };
        const endV = (sg) => (!sp.under ? '--' : ok ? T('seated', 'Seated') : `${(sg * (sp.x - this.xT)) > 0 ? '+' : '−'}${mmOf(err)} mm`);
        stats = [
          { id: 'p', label: J.prox, value: endV(-1), small: true, tone: ok ? 'teal' : '' },
          { id: 'd', label: J.dist, value: endV(1), small: true, tone: ok ? 'teal' : '' },
          { id: 'u', label: T('g3_pos', 'Position'), value: sp.under ? T('g3_under', 'Under the limb') : T('g3_beside', 'Beside it'), small: true, tone: sp.under ? 'teal' : '' },
        ];
      } else if (this.step === 2) {
        const pads = st.sites.filter(s => s.padded).length;
        wide = { label: T('padding', 'Padding'), value: `${pads}/2`, tone: pads === 2 ? 'teal' : '', meter: { value: pads / 2, segs: true }, caption: T('g3_cap_pad', 'Both sides of each joint'), captionTone: '' };
        stats = st.sites.map((s, i) => ({ id: `s${i}`, label: i === 0 ? J.prox : J.dist, value: s.padded ? T('g3_padded', 'Padded') : T('g3_bare', 'Bare bone'), small: true, tone: s.padded ? 'teal' : 'amber' }));
        stats.push({ id: 'al', label: T('res_align', 'Alignment'), value: st.s1, unit: '%', tone: 'teal' });
      } else if (this.step === 3) {
        const z = t.shapeZone, shaped = st.points.filter(p => p.done).length, press = st.points.filter(p => p.tight).length;
        if (this.press) {
          const f = this.pressF(n);
          wide = { label: T('pressure', 'Pressure'), value: Math.round(Math.min(1.1, f) * 100), unit: '%', tone: f > z[1] ? 'amber' : f >= z[0] ? 'teal' : '', meter: { value: Math.min(1, f / 1.1), zone: [z[0] / 1.1, z[1] / 1.1], tone: f > z[1] ? 'amber' : '' }, caption: f >= z[0] ? T('cap_release', 'Let go now') : T('cap_press', 'Keep pressing'), captionTone: f >= z[0] ? 'teal' : '' };
        } else {
          const fit = Math.round(100 * st.points.reduce((a, p) => a + Math.min(1, p.f / z[0]), 0) / st.points.length);
          wide = { label: T('contact', 'Contact'), value: fit, unit: '%', tone: fit >= 100 ? 'teal' : '', meter: { value: fit / 100, zone: [0.9, 1] }, caption: T('cap_contact', 'Walls against the limb'), captionTone: '' };
        }
        stats = [
          { id: 'pad', label: T('padding', 'Padding'), value: st.sites.filter(s => s.padded).length, unit: '/2', tone: 'teal' },
          { id: 'sh', label: T('shaped', 'Shaped'), value: shaped, unit: `/${st.points.length}`, tone: shaped === st.points.length ? 'teal' : '' },
          { id: 'pr', label: T('pressure_pts', 'Pressure points'), value: press, tone: press ? 'amber' : '' },
        ];
      } else if (this.step === 4) {
        const locked = st.straps.filter(s => s.state === 'locked').length, z = t.strapZone;
        const pl = this.pull ? st.straps[this.pull.i] : null;
        if (pl && pl.state === 'pulling') {
          const tn = pl.tension, inZ = tn >= z[0] && tn <= z[1];
          wide = { label: T('tension', 'Tension'), value: Math.round(tn * 100), unit: '%', tone: tn > t.strapTight ? 'red' : inZ ? 'teal' : '', meter: { value: tn, zone: z, mark: tn, tone: tn > t.strapTight ? 'red' : inZ ? '' : 'white' },
            caption: inZ ? T('cap_cinch', 'Cinch now') : tn > t.strapTight ? T('cap_tight', 'Too tight') : T('cap_wait', 'Wait for the arc'), captionTone: inZ ? 'teal' : tn > t.strapTight ? 'red' : '' };
        } else {
          const bad = this.badStrap() >= 0;
          wide = { label: T('straps', 'Straps'), value: `${locked}/3`, tone: locked === 3 && !bad ? 'teal' : '', meter: { value: locked / 3, tone: locked === 3 ? '' : 'white' },
            caption: bad ? T('cap_loosen', 'Loosen the tight strap') : T('cap_strap', 'Wrap and cinch'), captionTone: bad ? 'red' : '' };
        }
        const last = st.straps.filter(s => s.state === 'locked').slice(-1)[0];
        stats = [
          { id: 'st', label: T('straps', 'Straps'), value: locked, unit: '/3', tone: locked === 3 ? 'teal' : '' },
          { id: 'tn', label: T('last_tension', 'Last tension'), value: last ? Math.round(last.tension * 100) : '--', unit: last ? '%' : '', tone: last ? (last.tight ? 'red' : last.loose ? 'amber' : 'teal') : '' },
          { id: 'cms', label: T('cms', 'Distal check'), value: st.cms.state === 'bad' ? T('cms_bad', 'Cut off') : T('cms_wait', 'After straps'), small: true, tone: st.cms.state === 'bad' ? 'red' : '' },
        ];
      } else {
        const c = st.cms;
        let el2 = 0;
        if (c.state === 'checking') el2 = Math.min(c.refill, (n - c.t0) / 1000);
        else if (c.state === 'bad' || c.state === 'ok') el2 = c.refill;
        const back = c.state === 'checking' && (n - c.t0) / 1000 >= c.refill;
        wide = { label: T('g3_refill', 'Refill'), value: c.state === 'blanch' ? '--' : el2.toFixed(1), unit: 's', tone: back || c.state === 'bad' ? (c.tight ? 'red' : 'teal') : '',
          meter: { value: clamp(el2 / 4, 0, 1), zone: [0, 0.5], tone: el2 > 2 ? 'red' : '' },
          caption: c.state === 'blanch' ? T('g3_cap_blanch', 'Press until it is white') : c.state === 'checking' ? (back ? T('g3_cap_back', 'Colour back') : T('g3_cap_refill', 'Colour coming back…')) : T('g3_cap_nail', 'Press a nail'),
          captionTone: c.state === 'checking' ? 'teal' : '' };
        const rows = c.rows || [];
        stats = ['C', 'M', 'S'].map((k, i) => {
          const r = rows[i], lab = [T('circ', 'Circulation'), T('motor', 'Movement'), T('sens', 'Feeling')][i];
          const show = r && (c.state !== 'checking' || c.shown > i);
          return { id: k, label: lab, value: show ? (r.short || r.value) : c.state === 'checking' && c.shown === i ? T('cms_checking', 'Checking…') : '--', small: true, tone: show ? r.tone : '' };
        });
      }
      this.pp.set({ wide, stats });
      void force;
    }

    /* ═════════════ step away / carry on ═════════════
       snapshot() → a small JSON-safe object, or null while a move is half done. The next open of the same
       procedure on the same fracture carries it back as data.resume; boot() → restore() rebuilds that point
       on the fresh scene (built from the fresh open data) and returns the step to enter. */
    snapshot() {
      const st = this.st, sp = this.sp, c = st.cms;
      if (!this.ready || !this.alive || !this.S || st.finished || this.app.S !== st) return null;
      // finish the move first: the splint in the hand, a wall point / strap / nail held, the refill check running
      if (sp.drag || this.press || this.pull || this.blanch || c.state === 'blanch' || c.state === 'checking') return null;
      const r4 = v => rnd(+v || 0, 4);
      // (a slide still easing in or out: where it is going)
      const z = sp.anim && sp.anim.z1 !== undefined ? sp.anim.z1 : sp.z;
      return {
        v: 1,
        w: { inj: String(this.d.injury === undefined || this.d.injury === null ? '' : this.d.injury), reg: String(this.d.region || ''), seed: this.seed >>> 0 },
        step: this.step, t: rnd(clamp((performance.now() - st.t0) / 1000, 0, MAX_SNAP_T), 1),
        lay: { lk: sp.locked ? 1 : 0, u: sp.under ? 1 : 0, mv: sp.moved ? 1 : 0, dx: rnd(sp.x - this.xT, 5), dz: sp.under ? 0 : rnd(z - sp.z0, 5), s1: st.s1, rs: st.resets },
        pad: st.sites.map(s => (s.padded ? 1 : 0)),
        pts: st.points.map(p => [r4(p.f), p.done ? 1 : 0, p.tight ? 1 : 0]),
        // 0 open · 1 wrapped round the limb (not cinched) · 2 cinched at its tension; times cinched
        str: st.straps.map(s => [s.state === 'locked' ? 2 : s.state === 'open' ? 0 : 1, s.state === 'locked' ? r4(s.tension) : 0, s.locks | 0]),
        te: st.tightEver | 0,
        cms: { n: c.checks | 0, fx: c.fixed ? 1 : 0, bad: c.state === 'bad' ? 1 : 0 },
      };
    }
    // which fracture a snapshot was taken on: 'same', 'other' (another injury / limb / patient) or 'bad'
    limbMatch(w) {
      if (!plain(w)) return 'bad';
      const d = this.d, inj = d.injury === undefined || d.injury === null ? '' : String(d.injury);
      const same = String(w.inj === undefined || w.inj === null ? '' : w.inj) === inj && String(w.reg || '') === String(d.region || '') && num(w.seed, -1) === (this.seed >>> 0);
      return same ? 'same' : 'other';
    }
    // the splint set under the limb on its outline (step 1 done)
    setLaid() {
      const sp = this.sp;
      Object.assign(sp, { under: true, z: 0, drop: 1, anim: null, drag: null, hold: 0, moved: true, locked: true, ok: true, x: this.xT });
      this.placed = true;
      this.ghostG.visible = false;
      this.placeSplint(1);
    }
    // Rebuild the saved point → the step to enter. Only what the game itself can reach is taken back:
    // a step is entered only when every step before it is done; content of a step later than the one the
    // snapshot was on is never applied; an unreadable / out-of-range field starts its own step over (the
    // steps after it with it). Scores that follow from what is on the limb (shaping, strap grades) are
    // worked out again, not read.
    restore(r) {
      const st = this.st, sp = this.sp, tn = this.tune, c = st.cms;
      const at = intIn(r.step, 1, 5) || 1;
      const t = numIn(r.t, 0, MAX_SNAP_T);
      st.t0 = performance.now() - (t === null ? 0 : t) * 1000;
      let step = 1;

      // 1 · lay: set on the outline, or where it lay (beside the limb / under it, its offset)
      const L = plain(r.lay) ? r.lay : null;
      if (L) {
        const lk = bit(L.lk), u = bit(L.u), mv = bit(L.mv), rs = intIn(L.rs, 0, 999), s1 = intIn(L.s1, 35, 100);
        const dx = numIn(L.dx, -0.32, 0.32), dz = numIn(L.dz, -1, 1);
        if (lk === 1 && s1 !== null && rs !== null) {
          st.resets = rs; st.s1 = s1;
          this.setLaid();
          step = 2;
        } else if (lk === 0 && u >= 0 && mv >= 0 && rs !== null && dx !== null && (u === 1 || dz !== null)) {
          st.resets = rs;
          const snapZ = this.so.hw0 * 0.9 + this.R * 0.6;
          Object.assign(sp, { under: u === 1, moved: mv === 1 || u === 1, x: this.xT + dx, z: u === 1 ? 0 : clamp(sp.z0 + dz, snapZ * 0.95, sp.z0 + 0.12), drop: u === 1 ? 1 : 0, anim: null, drag: null, hold: 0 });
          this.placeSplint(sp.drop);
        } else this.restoreEmpty = true;
      } else this.restoreEmpty = true;

      // 2 · pads at the joints
      if (step === 2 && at >= 2) {
        const P = Array.isArray(r.pad) && r.pad.length === st.sites.length ? r.pad.map(bit) : null;
        if (P && P.every(b => b >= 0)) P.forEach((b, i) => { const s = st.sites[i]; s.padded = b === 1; s.k = b; s.pop = 0; });
        if (st.sites.every(s => s.padded)) step = 3;
      }

      // 3 · shaping: each point's press (set in the band, pressed too far, let go short of it)
      if (step === 3 && at >= 3) {
        const z0 = tn.shapeZone[0], z1 = tn.shapeZone[1], eps = 1e-3;
        const ok = Array.isArray(r.pts) && r.pts.length === st.points.length && r.pts.every(p => {
          if (!Array.isArray(p) || p.length < 3) return false;
          const f = numIn(p[0], 0, 1.08), dn = bit(p[1]), ti = bit(p[2]);
          if (f === null || dn < 0 || ti < 0) return false;
          if (ti === 1) return dn === 1 && f >= z1 - eps;            // pressed past the band: a pressure point
          return dn === 1 ? f >= z0 - eps && f <= z1 + eps : f < z0 + eps;
        });
        if (ok) r.pts.forEach((p, i) => { const pt = st.points[i]; pt.f = +p[0]; pt.done = bit(p[1]) === 1; pt.tight = bit(p[2]) === 1; pt.pop = 0; });
        if (st.points.every(p => p.done)) { st.shapeDone = true; st.s2 = this.shapeScore(); step = 4; }
      }

      // 4 · straps (open / wrapped / cinched at a tension) and 5 · the checks done so far
      if (step === 4 && at >= 4) {
        const te = intIn(r.te, 0, 99);
        const ok = te !== null && Array.isArray(r.str) && r.str.length === st.straps.length && r.str.every(x => {
          if (!Array.isArray(x) || x.length < 3) return false;
          const code = intIn(x[0], 0, 2), ten = numIn(x[1], 0, 1), lk = intIn(x[2], 0, 99);
          if (code === null || ten === null || lk === null) return false;
          return code === 2 ? lk >= 1 : ten === 0 && (code === 1 || lk === 0);
        });
        if (ok) {
          r.str.forEach((x, i) => {
            const s = st.straps[i], code = +x[0];
            s.state = ['open', 'wrapped', 'locked'][code]; s.k = code ? 1 : 0; s.tension = code === 2 ? +x[1] : 0; s.locks = +x[2];
            if (code === 2) this.strapGrade(s); else { s.quality = 0; s.tight = false; s.loose = false; }
          });
          // every strap pulled too tight on the limb now was counted when it was cinched
          st.tightEver = Math.max(te, st.straps.filter(s => s.tight).length);
        }
        // (the checks go with the straps: unreadable straps start step 4 over with no check done)
        const C = plain(r.cms) ? r.cms : {};
        const n = intIn(C.n, 0, 99), fx = bit(C.fx), bad = bit(C.bad);
        const cOk = ok && n !== null && fx >= 0 && bad >= 0 && (fx === 0 || n >= 1) && (bad === 0 || fx === 1);
        if (cOk) { c.checks = n; c.fixed = fx === 1; }
        if (st.straps.every(s => s.state === 'locked')) {
          // a failed check sends you back to loosen the tight strap; otherwise the check is next
          if (cOk && bad === 1 && this.badStrap() >= 0) c.state = 'bad';
          else { c.state = 'ready'; step = 5; }
        } else c.state = 'hidden';
      }
      this.refillTrough();
      return step;
    }
    // a snapshot that could not be rebuilt: open this splint again from the start (never a half-rebuilt scene)
    restartClean() {
      const a = this.app, d = Object.assign({}, this.d);
      delete d.resume;
      NEXT_NOTE = 'bad';
      try { a.procStart(d); } catch (e) { console.error('[splint] restart', e); }
      NEXT_NOTE = null;   // (the new game took it; the 2D fallback has no note)
    }
    // preview only (?resume=<stage>): set a mid-game point the way playing leaves it (no move half done),
    // step away and open again from the snapshot
    previewPark(stage) {
      if (!this.alive || !this.ready || NZA.inGame) return;
      const st = this.st, sp = this.sp, s = String(stage || '').toLowerCase();
      const steps = { lay: 1, pad: 2, shape: 3, strap: 4, loosen: 4, cms: 5 };
      const to = steps[s] || 1;
      st.resets = 1;
      // (under the limb, 50 mm short of the outline: past the tolerance, so it does not set itself)
      Object.assign(sp, { under: true, z: 0, drop: 1, anim: null, drag: null, moved: true, x: this.xT + 0.05 });
      this.placeSplint(1);
      if (to >= 2) {
        st.s1 = 93; this.setLaid();
        st.sites[0].padded = true; st.sites[0].k = 1;
      }
      if (to >= 3) {
        st.sites[1].padded = true; st.sites[1].k = 1;
        // two set in the band, one pressed too far (a pressure point), one let go short
        [0.84, 0.9, 1.04, 0.41].forEach((f, i) => { const p = st.points[i]; if (p) { p.f = f; p.done = i < 3; p.tight = i === 2; } });
      }
      if (to >= 4) {
        st.points.forEach((p, i) => { if (!p.done) { p.f = [0.86, 0.88, 0.85, 0.9, 0.87][i % 5]; p.done = true; } });
        st.shapeDone = true; st.s2 = this.shapeScore();
        const cinch = (i, ten) => { const x = st.straps[i]; x.state = 'locked'; x.k = 1; x.tension = ten; x.locks = 1; this.strapGrade(x); if (x.tight) st.tightEver += 1; };
        cinch(0, 0.68);
        if (s === 'strap') Object.assign(st.straps[1], { state: 'wrapped', k: 1 });
        else {
          cinch(1, s === 'loosen' ? 0.93 : 0.71); cinch(2, 0.64);
          if (s === 'loosen') Object.assign(st.cms, { checks: 1, fixed: true, state: 'bad' });
          else st.cms.state = 'ready';
        }
      }
      this.step = to;
      st.t0 = performance.now() - 74000;
      const snap = this.snapshot();
      if (!snap) return;
      const d = JSON.parse(JSON.stringify(this.d));
      d.resume = JSON.parse(JSON.stringify(snap));
      NZA.demo(APP, d);
    }
    // the running game's progress (emulator scenarios: Splint3D.debug())
    debugState() {
      const st = this.st, sp = this.sp || {}, c = st.cms;
      return {
        ready: !!this.ready, alive: !!this.alive, step: this.step, resumed: !!this.resumed, note: this.noteShown || null, finished: !!st.finished,
        t: rnd((performance.now() - st.t0) / 1000, 1), pause: !!(this.pp && this.pp.el && this.pp.el.querySelector('.pp-pause') && this.pp.el.querySelector('.pp-pause').style.display !== 'none'),
        lay: { locked: !!sp.locked, under: !!sp.under, dx: rnd((sp.x || 0) - (this.xT || 0), 4), s1: st.s1, resets: st.resets, placed: !!this.placed },
        pads: st.sites.map(s => !!s.padded),
        pts: st.points.map(p => [rnd(p.f, 3), p.done ? 1 : 0, p.tight ? 1 : 0]), shapeDone: !!st.shapeDone, s2: st.s2,
        straps: st.straps.map(s => ({ state: s.state, k: rnd(s.k, 3), tension: rnd(s.tension, 3), tight: !!s.tight, loose: !!s.loose, quality: Math.round(s.quality), locks: s.locks })),
        tightEver: st.tightEver, cms: { state: c.state, checks: c.checks, fixed: !!c.fixed },
      };
    }

    /* ─────────────── preview: open at a stage ─────────────── */
    jump(stage) {
      if (!this.ready) { this.pendingJump = stage; return; }
      const st = this.st, sp = this.sp, n = this.simMs(), real = performance.now(), q = new URLSearchParams(location.search);
      this.freezeAt = n;
      const s = String(stage || 'place').toLowerCase();
      const order = ['place', 'aligned', 'pad', 'shape', 'strap', 'tension', 'cmsready', 'cms', 'cmsbad', 'done'];
      const lvl = Math.max(0, order.indexOf(s));
      st.t0 = real - 97000;
      if (s === 'place') return;
      // 1 · under the limb, on the outline
      sp.under = true; sp.z = 0; sp.drop = 1; sp.anim = null; sp.moved = true;
      sp.x = this.xT + (s === 'aligned' ? 0.006 : 0);
      this.placeSplint(1);
      if (s === 'aligned') { sp.hold = -1e9; this.frameStep(1, true); this.pp.set({ text: this.text() }); return; }
      st.s1 = 93; sp.locked = true; this.placed = true; this.ghostG.visible = false;
      this.placeSplint(1);
      if (lvl === 2) { this.enter(2, true); this.padSite(0, true); st.sites[0].pop = 0; this.refreshTools(); return; }
      st.sites.forEach(x => { x.padded = true; x.k = 1; x.pop = 0; });
      if (s === 'shape') {
        this.enter(3, true);
        st.points.forEach((p, i) => { if (i < 3) { p.f = [0.84, 0.9, 0.87][i]; p.done = true; } });
        this.press = { i: 3, f0: 0.61, t0: n, rate: 1 }; st.points[3].f = 0.61;
        this.freeze = true; this.lmb = true;
        this.refillTrough(); this.refreshTools(); this.panel(true);
        return;
      }
      st.points.forEach((p, i) => { p.f = [0.84, 0.9, 0.87, 0.92, 0.88, 0.86, 0.9, 0.85, 0.89][i] || 0.86; p.done = true; p.pop = 0; });
      st.shapeDone = true; st.s2 = 91;
      this.refillTrough();
      if (s === 'strap' || s === 'tension') {
        this.enter(4, true);
        const a = st.straps[0]; a.state = 'locked'; a.k = 1; a.tension = 0.68; a.quality = 96; a.locks = 1;
        if (s === 'tension') { const b = st.straps[1]; b.state = 'pulling'; b.k = 1; b.tension = 0.64; this.pull = { i: 1, t0: n - 1200 }; this.freeze = true; this.lmb = true; }
        this.refreshTools(); this.panel(true);
        return;
      }
      st.straps.forEach((x, i) => {
        x.state = 'locked'; x.k = 1; x.locks = 1;
        x.tension = s === 'cmsbad' && i === 1 ? 0.93 : [0.66, 0.71, 0.64][i];
        x.quality = x.tension > 0.9 ? 30 : [96, 92, 95][i]; x.tight = x.tension > 0.9; if (x.tight) st.tightEver += 1;
      });
      st.cms.state = 'ready';
      if (s === 'cmsready') { this.enter(5, true); this.refreshTools(); return; }
      if (s === 'cms') {
        this.enter(5, true);
        this.cmsCheck(this.checkNail, n - 700);
        this.freeze = true; this.freezeBlanch = 0.45;
        this.refreshTools(); this.panel(true);
        return;
      }
      if (s === 'cmsbad') {
        this.enter(5, true);
        this.cmsCheck(this.checkNail, n - 60000);
        const c = st.cms; c.shown = 3; c.state = 'bad'; c.fixed = true;
        this.pp.set({ title: this.title() });
        this.pp.flash('bad', T('g3_cms_fail', 'No good pulse below the splint: a strap is too tight. Hold on the strap marked red to loosen it and pull it again, then check again.'), 0);
        this.refreshTools(); this.panel(true);
        return;
      }
      // done: checked, recorded, the record card
      this.jumping = true;
      this.enter(5, true);
      this.cmsCheck(this.checkNail, n - 60000);
      st.cms.shown = 3; st.cms.state = 'ok';
      void q;
      this.finish();
    }
    // screen positions of the things to click / drag (the emulator scenario uses these)
    targets() {
      if (!this.ready) return null;
      const st = this.st, P = v => this.toPx(v);
      const o = this.so;
      return {
        step: this.step, cms: st.cms.state,
        splint: P(this.sw(0, o.yF + o.depth * 0.5, 0)),
        ghost: P(V3(this.xT, this.splint.position.y + o.yF + o.depth * 0.5, 0)),
        ghostAt: P(V3(this.xT, this.yb + o.yF + o.depth * 0.5, 0)),
        sites: st.sites.map((s, i) => Object.assign(P(this.sitePos(i)), { padded: s.padded })),
        points: st.points.map((p, i) => Object.assign(P(this.pointPos(i)), { done: p.done, f: p.f })),
        straps: st.straps.map((s, i) => Object.assign(P(this.strapMarkAt(i)), { state: s.state, tension: s.tension, tight: s.tight })),
        nail: P(this.checkNail.nail.getWorldPosition(V3())),
      };
    }

    /* ─────────────── teardown ─────────────── */
    dispose() {
      if (!this.alive) return;
      this.alive = false;
      if (CURRENT === this) CURRENT = null;
      const app = this.app;
      window.removeEventListener('blur', this.onBlur);
      window.removeEventListener('resize', this.onResize);
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[splint] dispose', e); } this.S = null; }
      this.bin.forEach(x => { try { x.dispose(); } catch (e) { /* gone */ } });
      this.bin.clear();
      [this.stage, this.curEl, this.loadEl].forEach(nd => { if (nd && nd.parentNode) nd.parentNode.removeChild(nd); });
      app.full = false; app.opaque = false; app.camInput = true;
      app.el.classList.remove('nza-full');
      app.keys = {}; app.keysUp = {};
      if (app.S === this.st) this.st.active = false;
    }
  }
  // distance from point p to segment ab (px)
  function segDist(p, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    const t = l2 > 0 ? clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0, 1) : 0;
    return Math.hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t));
  }

  window.Splint3D = {
    broken: false,
    ok() {
      if (this.broken || !window.NZA3D || !THREE) return false;
      if (!NZA.inGame && /[?&]no3d=1\b/.test(location.search)) return false;
      try { return !!NZA3D.supported(); } catch (e) { return false; }
    },
    start(app, data) { return new Game(app, data); },
    // the running game's progress, or null (emulator scenarios)
    debug() { return CURRENT && CURRENT.alive ? CURRENT.debugState() : null; },
  };
  window.SplintDebug = () => window.Splint3D.debug();
})();
