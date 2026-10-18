/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Splint (app 'splint')             module: splint
   In-world splinting over a straight-down game camera on the broken limb, on the
   shared procedure HUD (NZA.ui.ProcPanel: left column + right tool belt).
   The splint itself is a real-time 3D model (three.js) drawn over the game with
   the game camera's lens, so it sits on the limb with correct perspective; where
   it passes under the limb the limb shows through (it lies in the channel).

     1 Lay the splint    drag it onto the limb; Q / E turn it, arrows nudge,
                         Shift fine, X start over, right-drag turns the view,
                         wheel zooms. Both ends must sit on their joints
                         (anchors 'prox' / 'dist'); it sets after a steady hold
                         or with Space.
     2 Pad & shape       2 Padding: click the bony points to pad them.
                         3 Shape: press and hold along the splint until the
                         walls close on the limb (stop in the band - too much
                         leaves a pressure point).
     3 Strap & check     4 Straps: click a strap to wrap it, click / Space when
                         the tension needle is in the band. 5 Check: click the
                         toes / fingers ('cms' anchor) for circulation, motor and
                         sensation. A strap that is too tight cuts the pulse off:
                         click it to loosen, cinch again and re-check.
   The splint model carries a printed foam liner (centimetre rule, joint lines, device print, warning
   sticker - generic labelling only), a stitched edge binding, riveted strap tabs, D-rings and numbered
   pull tabs; the limb lies on it (hidden under the limb, contact shadow round it, strap shadows on it).
   The finished splint is written up in the record card (grade ring + a top-view map of joints, pads,
   shaping points and strap tensions).
   Also hosts the mobility card (wheelchair / pushing / crutches) in 'hud' mode: chair drawing with
   moving tread and per-wheel drive bars, rolling speed / distance counters, inclinometer, blocked note;
   crutch gait drawing (tips, good foot, splinted foot held off the ground), step counter.

   Lua → JS   open { mode = 'proc', locale, region, regionLabel, device, deviceLabel, deviceModel,
                     limb, segment, joints { prox, dist, cms }, fracture { kind, kindLabel, bone,
                     boneLabel, displaced, angle }, open, dressed, severity, pulse, pulseWhy, hr,
                     sys, refill, responsive, name, sex, pain, size { width, depth, wall,
                     limbRadius }, segLen, fov, upright, tune, keys }
              open { mode = 'hud', locale, hud }     hud (data)    hudOff    result (outcome)
              hud data: chair/push { kind, title, sub, state, speed, max, slope, turn, dist, blocked, keys }
                        crutch     { kind, title, sub, state, moving, steps, side ('l'|'r'), keys }
              anchors { prox, dist, cms, core }
   JS → Lua   splint:finish (result) · splint:abort · splint:done · splint:close
   Preview    index.html?app=splint&stage=place|aligned|pad|shape|strap|cmsready|cms|cmsbad|done
              (prefix arm- for the forearm: arm, arm-done …) · hud-chair|hud-push|hud-blocked|hud-crutch
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'splint';
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(x => { s = s.replace(/%[sd]/, x); }); return s; };

  /* ─────────────── 2D vectors (screen px) ─────────────── */
  const v = (x, y) => ({ x, y });
  const add = (a, b) => v(a.x + b.x, a.y + b.y);
  const sub = (a, b) => v(a.x - b.x, a.y - b.y);
  const mul = (a, k) => v(a.x * k, a.y * k);
  const dot = (a, b) => a.x * b.x + a.y * b.y;
  const len = a => Math.hypot(a.x, a.y);
  const perp = a => v(-a.y, a.x);
  const rotv = (a, r) => { const c = Math.cos(r), s = Math.sin(r); return v(a.x * c - a.y * s, a.x * s + a.y * c); };
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
  const easeInOut = t => { t = clamp(t, 0, 1); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const keyLabel = c => ({ Space: 'Space', Enter: 'Enter', Escape: 'ESC', ShiftLeft: 'Shift' })[c] || String(c || '').replace(/^Key|^Digit/, '');
  const mm = m => Math.round(m * 1000);

  const DEF_TUNE = {
    tolerance: 0.035, angleTolerance: 8, lockHold: 0.7, rotateSpeed: 55, nudgeSpeed: 0.2, fine: 0.22,
    shapePoints: { leg: 6, arm: 5 }, shapeSeconds: 1.15, shapeClick: 0.18, shapeZone: [0.72, 1.0],
    strapZone: [0.55, 0.82], strapTight: 0.88, strapPeriod: 1.7,
  };
  const DEF_KEYS = { rotateLeft: 'KeyQ', rotateRight: 'KeyE', reset: 'KeyX', set: 'Space' };
  const SIZE = {
    leg: { width: 0.15, depth: 0.07, wall: 0.01, limbRadius: 0.055 },
    arm: { width: 0.105, depth: 0.05, wall: 0.008, limbRadius: 0.04 },
  };
  // how far the splint reaches past each joint (m) - immobilise the joint above and below
  const EXT = { leg: { lower: [0.085, 0.075], upper: [0.05, 0.13] }, arm: { lower: [0.05, 0.07], upper: [0.04, 0.08] } };
  // how far the limb itself continues past each joint (m) - for the "lies in the channel" mask
  const LIMB_MORE = { leg: { lower: [0.42, 0.1], upper: [0.06, 0.44] }, arm: { lower: [0.27, 0.15], upper: [0.04, 0.27] } };
  const STRAP_W = { leg: 0.042, arm: 0.034 };
  const COL = { teal: '#08afa2', tealHi: '#2fe0d0', red: '#e5484d', redHi: '#ff7478', amber: '#e5a50a', amberHi: '#f3c35a', white: '#ffffff' };

  /* ═════════════════════ procedural textures ═════════════════════ */
  const cvs = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
  function rng(seed) { let s = (seed >>> 0) || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }
  function normalFromHeight(hc, strength = 2) {
    const w = hc.width, h = hc.height;
    const src = hc.getContext('2d').getImageData(0, 0, w, h).data;
    const out = cvs(w, h), oc = out.getContext('2d'), id = oc.createImageData(w, h), d = id.data;
    const H = (x, y) => src[((((y % h) + h) % h) * w + (((x % w) + w) % w)) * 4] / 255;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const dx = (H(x + 1, y) - H(x - 1, y)) * strength, dy = (H(x, y + 1) - H(x, y - 1)) * strength;
        const l = Math.hypot(dx, dy, 1), i = (y * w + x) * 4;
        d[i] = (-dx / l * 0.5 + 0.5) * 255; d[i + 1] = (dy / l * 0.5 + 0.5) * 255; d[i + 2] = (1 / l * 0.5 + 0.5) * 255; d[i + 3] = 255;
      }
    }
    oc.putImageData(id, 0, 0);
    return out;
  }
  function tex(c, repeat, srgb) {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    if (repeat) t.repeat.set(repeat[0], repeat[1]);
    if (srgb) t.encoding = THREE.sRGBEncoding;
    t.anisotropy = 4;
    return t;
  }
  const lin = hex => new THREE.Color(hex).convertSRGBToLinear();

  // closed-cell foam: tiny dimples (tiled - foot plate pad, palm roll)
  function foamTextures() {
    const n = 256, r = rng(91);
    const h = cvs(n, n), hc = h.getContext('2d');
    hc.fillStyle = '#909090'; hc.fillRect(0, 0, n, n);
    for (let i = 0; i < 1600; i++) {
      const x = r() * n, y = r() * n, rad = 0.8 + r() * 2.6;
      const g = hc.createRadialGradient(x, y, 0, x, y, rad);
      g.addColorStop(0, `rgba(30,30,30,${0.35 + r() * 0.4})`); g.addColorStop(1, 'rgba(30,30,30,0)');
      hc.fillStyle = g; hc.beginPath(); hc.arc(x, y, rad, 0, Math.PI * 2); hc.fill();
    }
    const c = cvs(n, n), cc = c.getContext('2d');
    cc.fillStyle = '#ffffff'; cc.fillRect(0, 0, n, n);
    cc.globalAlpha = 0.08; cc.drawImage(h, 0, 0); cc.globalAlpha = 1;
    return { map: tex(c, [6, 6], true), normal: tex(normalFromHeight(h, 2.4), [6, 6]) };
  }

  // The printed foam liner of the channel (one texture over the whole inner surface, u across the
  // channel from rim to rim, v along it from the proximal end): closed-cell dimples, a centimetre
  // rule along one wall, joint lines across the floor, the device print along the other wall and a
  // warning sticker. Generic device labelling only - no brand.
  function linerTextures(o) {
    const W = 512, H = 2048, r = rng(o.kind === 'leg' ? 191 : 233);
    const c = cvs(W, H), x = c.getContext('2d');
    const h = cvs(W, H), hx = h.getContext('2d');
    x.fillStyle = '#3d454c'; x.fillRect(0, 0, W, H);
    hx.fillStyle = '#8c8c8c'; hx.fillRect(0, 0, W, H);
    // tonal mottling + wear along the floor
    for (let i = 0; i < 30; i++) {
      const gx = r() * W, gy = r() * H, gr = 40 + r() * 120, dark = r() > 0.5;
      const g = x.createRadialGradient(gx, gy, 0, gx, gy, gr);
      g.addColorStop(0, dark ? `rgba(10,14,18,${0.03 + r() * 0.04})` : `rgba(160,175,185,${0.02 + r() * 0.025})`); g.addColorStop(1, 'rgba(0,0,0,0)');
      x.fillStyle = g; x.fillRect(gx - gr, gy - gr, gr * 2, gr * 2);
    }
    const floor = x.createLinearGradient(0, 0, W, 0);
    floor.addColorStop(0, 'rgba(0,0,0,.18)'); floor.addColorStop(0.18, 'rgba(0,0,0,0)'); floor.addColorStop(0.5, 'rgba(255,255,255,.035)'); floor.addColorStop(0.82, 'rgba(0,0,0,0)'); floor.addColorStop(1, 'rgba(0,0,0,.18)');
    x.fillStyle = floor; x.fillRect(0, 0, W, H);
    // closed-cell dimples
    for (let i = 0; i < 24000; i++) {
      const px = r() * W, py = r() * H, rad = 0.6 + r() * 1.8;
      hx.fillStyle = `rgba(28,28,28,${0.2 + r() * 0.4})`; hx.beginPath(); hx.arc(px, py, rad, 0, 6.2832); hx.fill();
      if (r() < 0.2) { x.fillStyle = `rgba(0,0,0,${0.05 + r() * 0.06})`; x.fillRect(px - rad * 0.5, py - rad * 0.5, rad, rad); }
    }
    const L = o.L, P = o.perim, ku = W / P, kv = H / L;
    // draw in millimetres at (u, v) metres; rot 90° = along the splint
    const mmAt = (um, vm, rot) => { const cs = Math.cos(rot), sn = Math.sin(rot), k = 0.001; x.setTransform(ku * k * cs, kv * k * sn, -ku * k * sn, kv * k * cs, um * ku, vm * kv); };
    const ink = 'rgba(214,224,228,.82)', inkDim = 'rgba(214,224,228,.5)';
    const font = (mm, w = 600) => `${w} ${mm}px "JetBrains Mono", monospace`;
    // centimetre rule along the left wall (zero at the proximal end)
    const uR = P * 0.2;
    for (let cm = 0; cm <= Math.floor(L * 100); cm++) {
      const vm = cm / 100;
      const long = cm % 5 === 0;
      mmAt(uR, vm, 0);
      x.fillStyle = long ? ink : inkDim;
      x.fillRect(-(long ? 9 : 5.5), -0.35, long ? 9 : 5.5, 0.7);
      for (let mmk = 1; mmk < 10 && cm < Math.floor(L * 100); mmk++) { if (mmk !== 5) x.fillRect(-2.2, mmk - 0.18, 2.2, 0.36); else x.fillRect(-3.6, mmk - 0.22, 3.6, 0.44); }
      if (long && cm > 0) {
        mmAt(uR + 0.0062, vm, Math.PI / 2);
        x.fillStyle = ink; x.font = font(5.6, 700); x.textAlign = 'center'; x.textBaseline = 'middle';
        x.fillText(String(cm), 0, 0);
      }
    }
    mmAt(uR - 0.0005, 0, 0); x.fillStyle = inkDim; x.fillRect(-0.3, 0, 0.6, L * 1000);
    // joint lines across the floor (line the joints up with them)
    (o.sites || []).forEach((s, i) => {
      const vm = s.x + L / 2;
      mmAt(0, vm, 0);
      x.fillStyle = 'rgba(47,224,208,.85)';
      for (let u = 6; u < P * 1000 - 6; u += 5) x.fillRect(u, -0.45, 3, 0.9);
      mmAt(P * 0.7, vm + (i === 0 ? -0.006 : 0.006), Math.PI / 2);
      x.fillStyle = 'rgba(47,224,208,.95)'; x.font = font(5.4, 800); x.textAlign = i === 0 ? 'right' : 'left'; x.textBaseline = 'middle';
      x.fillText(`${i === 0 ? '▲ ' : ''}${(i === 0 ? o.print.prox : o.print.dist).toUpperCase()}${i === 0 ? '' : ' ▼'}`, 0, 0);
    });
    // device print along the right wall, repeated
    const line = `${o.print.model} · ${o.print.name.toUpperCase()} · ${o.print.use.toUpperCase()}`;
    x.font = font(4.2, 600); x.textAlign = 'left'; x.textBaseline = 'middle';
    const tw = x.measureText(line).width + 60;
    for (let vmm = 40; vmm < L * 1000 - 60; vmm += tw) {
      mmAt(P * 0.6, vmm / 1000, Math.PI / 2);
      x.fillStyle = inkDim; x.fillText(line, 0, 0);
    }
    // warning sticker near the distal end
    const vS = Math.max(0.06, (o.sites && o.sites[1] ? o.sites[1].x + L / 2 : L * 0.8) - 0.075);
    mmAt(P * 0.36, vS, Math.PI / 2);
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
    const map = tex(c, null, true), normal = tex(normalFromHeight(h, 2.2));
    [map, normal].forEach(t => { t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping; t.flipY = false; t.anisotropy = 8; });
    return { map, normal };
  }

  // nylon webbing: ribs along the strap, bound edges, stitch lines, hook-and-loop patch at the free end
  function webbingTextures() {
    const w = 64, h = 1024, r = rng(17);
    const c = cvs(w, h), cc = c.getContext('2d');
    cc.fillStyle = '#1c1f22'; cc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { cc.fillStyle = x % 4 ? 'rgba(255,255,255,.035)' : 'rgba(0,0,0,.25)'; cc.fillRect(x, 0, 1, h); }
    for (let y = 0; y < h; y += 3) { cc.fillStyle = 'rgba(255,255,255,.025)'; cc.fillRect(0, y, w, 1); }
    cc.fillStyle = '#111315'; cc.fillRect(0, 0, 4, h); cc.fillRect(w - 4, 0, 4, h);
    cc.fillStyle = 'rgba(15,180,168,.85)';
    for (let y = 0; y < h; y += 8) { cc.fillRect(6, y, 2, 5); cc.fillRect(w - 8, y, 2, 5); }
    // hook-and-loop patch (last fifth), box-stitched
    const p0 = Math.round(h * 0.8);
    cc.fillStyle = '#3a3e42'; cc.fillRect(5, p0, w - 10, h - p0 - 6);
    for (let i = 0; i < 2600; i++) { const l = 50 + r() * 50; cc.fillStyle = `rgba(${l},${l + 3},${l + 6},.8)`; cc.fillRect(5 + r() * (w - 10), p0 + r() * (h - p0 - 6), 1, 1 + r() * 2); }
    cc.strokeStyle = 'rgba(15,180,168,.8)'; cc.lineWidth = 1.2; cc.setLineDash([3, 2]);
    cc.strokeRect(8, p0 + 3, w - 16, h - p0 - 12);
    cc.beginPath(); cc.moveTo(8, p0 + 3); cc.lineTo(w - 8, h - 9); cc.moveTo(w - 8, p0 + 3); cc.lineTo(8, h - 9); cc.stroke();
    const hh = cvs(w, h), hc = hh.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { hc.fillStyle = x % 4 ? '#a0a0a0' : '#606060'; hc.fillRect(x, 0, 1, h); }
    hc.fillStyle = '#b8b8b8'; hc.fillRect(0, 0, 3, h); hc.fillRect(w - 3, 0, 3, h);
    for (let i = 0; i < 3000; i++) { hc.fillStyle = r() > 0.5 ? '#c4c4c4' : '#5a5a5a'; hc.fillRect(5 + r() * (w - 10), p0 + r() * (h - p0 - 6), 1, 1); }
    const m = tex(c, [1, 1], true), n = tex(normalFromHeight(hh, 3));
    [m, n].forEach(t => { t.wrapT = THREE.ClampToEdgeWrapping; });
    return { map: m, normal: n };
  }
  // woven edge binding round the rims: fine weave across, a stitch line down the middle
  function bindingTextures() {
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
    return { map: tex(c, null, true), normal: tex(normalFromHeight(hh, 2.6)) };
  }
  // brushed / moulded shell grain
  function shellTextures() {
    const n = 256, r = rng(7);
    const h = cvs(n, n), hc = h.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, n, n);
    for (let i = 0; i < 5000; i++) { hc.fillStyle = `rgba(${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},.06)`; hc.fillRect(r() * n, r() * n, 1 + r() * 2, 1); }
    return { normal: tex(normalFromHeight(h, 0.6), [8, 14]) };
  }
  // the numbered pull tab at the free end of each strap
  function tabNumberTexture(n) {
    const c = cvs(64, 32), x = c.getContext('2d');
    x.fillStyle = '#0b8379'; x.fillRect(0, 0, 64, 32);
    x.fillStyle = 'rgba(255,255,255,.12)'; x.fillRect(0, 0, 64, 3);
    x.fillStyle = '#e9fffb'; x.font = '800 22px "JetBrains Mono", monospace'; x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillText(String(n), 32, 17);
    const t = tex(c, null, true);
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    return t;
  }
  // studio-ish environment for reflections (up = +z)
  function envTexture(renderer, opts = {}) {
    const s = new THREE.Scene();
    const geo = new THREE.SphereGeometry(10, 48, 24);
    const pos = geo.attributes.position, cols = [];
    const sky = new THREE.Color(opts.sky || 0xc9d5df), gnd = new THREE.Color(opts.ground || 0x2a2c2e), hor = new THREE.Color(opts.horizon || 0x8d939a);
    for (let i = 0; i < pos.count; i++) {
      const z = pos.getZ(i) / 10;
      const c = z > 0 ? hor.clone().lerp(sky, smooth(0, 0.7, z)) : hor.clone().lerp(gnd, smooth(0, 0.35, -z));
      cols.push(c.r, c.g, c.b);
    }
    geo.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
    s.add(new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
    const panel = (x, y, z, w, h, k) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(k, k, k * 0.97), side: THREE.DoubleSide }));
      m.position.set(x, y, z); m.lookAt(0, 0, 0); s.add(m);
    };
    panel(-3.5, 4.5, 7, 5, 3, 5.5);
    panel(6, -3, 5, 3, 6, 2.2);
    panel(0, 0, 9, 4, 4, 1.6);
    const pm = new THREE.PMREMGenerator(renderer);
    const rt = pm.fromScene(s, 0.035);
    pm.dispose();
    geo.dispose();
    return rt.texture;
  }

  /* ═════════════════════ 3D SPLINT (overlay renderer) ═════════════════════ */
  function SplintGL(canvas) {
    if (!window.THREE) return null;
    let R;
    try {
      R = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, premultipliedAlpha: true, powerPreference: 'high-performance' });
    } catch (e) { console.warn('[splint] WebGL unavailable', e); return null; }
    R.setPixelRatio(1);
    R.setClearColor(0x000000, 0);
    R.outputEncoding = THREE.sRGBEncoding;
    R.toneMapping = THREE.ACESFilmicToneMapping;
    R.toneMappingExposure = 1.05;
    const scene = new THREE.Scene();
    const cam = new THREE.PerspectiveCamera(50, 1, 1, 100000);
    scene.environment = envTexture(R);
    const key = new THREE.DirectionalLight(0xfff1e0, 1.55); key.position.set(-0.45, 0.62, 1); scene.add(key);
    const fill = new THREE.DirectionalLight(0xd6e8ff, 0.5); fill.position.set(0.7, -0.5, 0.6); scene.add(fill);
    const hemi = new THREE.HemisphereLight(0xeef4ff, 0x2c2c28, 0.45); hemi.position.set(0, 0, 1); scene.add(hemi);

    // ── where the splint passes under the limb it is hidden (the limb lies on it), and the foam right
    //    next to the limb is darkened (contact shadow) - screen-space capsule fed every frame ──
    const FU = { uLimbA: { value: new THREE.Vector2() }, uLimbB: { value: new THREE.Vector2() }, uLimbR: { value: 0 }, uFade: { value: 0 }, uOpacity: { value: 1 } };
    const fadeMat = (mat, keyName, floor = 0.1, ao = 0) => {
      mat.transparent = true;
      mat.onBeforeCompile = sh => {
        Object.assign(sh.uniforms, FU);
        sh.fragmentShader = sh.fragmentShader
          .replace('#include <common>', `#include <common>
uniform vec2 uLimbA; uniform vec2 uLimbB; uniform float uLimbR; uniform float uFade; uniform float uOpacity;
float nzaSeg(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0); return length(pa - ba * h); }`)
          .replace('#include <dithering_fragment>', `#include <dithering_fragment>
{ float dd = nzaSeg(gl_FragCoord.xy, uLimbA, uLimbB);
  float kk = (1.0 - smoothstep(uLimbR * 0.84, uLimbR * 1.0, dd)) * uFade;
  ${ao ? `float oc = (1.0 - smoothstep(uLimbR * 0.95, uLimbR * 1.6, dd)) * uFade; gl_FragColor.rgb *= 1.0 - oc * ${ao.toFixed(3)};` : ''}
  gl_FragColor.a *= uOpacity * (1.0 - kk * ${(1 - floor).toFixed(3)}); }`);
      };
      mat.customProgramCacheKey = () => `nzafade-${keyName}`;
      return mat;
    };
    const foamT = foamTextures(), webT = webbingTextures(), shellT = shellTextures(), bindT = bindingTextures();
    const M = {
      foam: fadeMat(new THREE.MeshStandardMaterial({ color: 0xffffff, normalScale: new THREE.Vector2(0.75, 0.75), roughness: 0.93, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.55 }), 'foam', 0.0, 0.62),
      shell: fadeMat(new THREE.MeshPhysicalMaterial({ color: lin('#07887e'), normalMap: shellT.normal, normalScale: new THREE.Vector2(0.25, 0.25), roughness: 0.4, metalness: 0, clearcoat: 0.6, clearcoatRoughness: 0.22, side: THREE.DoubleSide, envMapIntensity: 0.8 }), 'shell', 0.0),
      bind: fadeMat(new THREE.MeshStandardMaterial({ map: bindT.map, normalMap: bindT.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.78, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.6 }), 'bind', 0.04),
      cap: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#0a7f76'), roughness: 0.5, side: THREE.DoubleSide }), 'cap', 0.0),
      pad: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#e6ecee'), normalMap: foamT.normal, normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.97, envMapIntensity: 0.6 }), 'pad', 0.3),
      roll: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#59666c'), normalMap: foamT.normal, roughness: 0.92 }), 'roll', 0.15),
      plateFoam: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#3c444b'), map: foamT.map, normalMap: foamT.normal, roughness: 0.95 }), 'pfoam', 0.12),
      strap: new THREE.MeshStandardMaterial({ map: webT.map, normalMap: webT.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.68, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.7 }),
      // an open strap lies on the ground: the limb covers it
      strapO: fadeMat(new THREE.MeshStandardMaterial({ map: webT.map, normalMap: webT.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.68, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.7 }), 'strapO', 0.0),
      metal: new THREE.MeshStandardMaterial({ color: lin('#a3acb2'), metalness: 0.95, roughness: 0.26, envMapIntensity: 1.35 }),
      tab: new THREE.MeshPhysicalMaterial({ color: lin('#0b8379'), roughness: 0.42, clearcoat: 0.6, clearcoatRoughness: 0.25 }),
      dark: new THREE.MeshStandardMaterial({ color: lin('#16191c'), roughness: 0.55, metalness: 0.2 }),
    };
    const numMats = [1, 2, 3].map(n => new THREE.MeshPhysicalMaterial({ map: tabNumberTexture(n), roughness: 0.45, clearcoat: 0.5, clearcoatRoughness: 0.3 }));
    const group = new THREE.Group();
    scene.add(group);
    let G = null;
    let dirty = true;
    let lastFov = 0;

    const NX = 96, K = 24, RC = 6;
    const RING = (K + 1) + RC + (K + 1) + RC;
    const BV = RC + 2;                                   // binding verts per rim per slice
    const JS = K + RC + 1 + Math.floor(K / 2);           // ring seam (underneath, out of sight)
    const RIM_R = Array.from({ length: BV }, (_, r) => K + r);
    const RIM_L = Array.from({ length: BV }, (_, r) => (2 * K + RC + 1 + r) % RING);

    function disposeGroup() {
      group.traverse(o => { if (o.geometry) o.geometry.dispose(); });
      while (group.children.length) group.remove(group.children[0]);
    }

    // cross-section of the trough at local x for the current shaping state
    function profile(x) {
      const o = G.o, P = G.P;
      const t = (x + o.L / 2) / o.L;
      // shaping: smooth interpolation between the pressed points (ends fade out past the last point)
      let shaped = 0, over = 0;
      const pts = P.points;
      if (pts.length) {
        const sv = p => Math.min(1, p.f / P.zone0);
        if (x <= pts[0].x) shaped = sv(pts[0]) * Math.exp(-((x - pts[0].x) ** 2) / (2 * o.sig * o.sig));
        else if (x >= pts[pts.length - 1].x) { const q = pts[pts.length - 1]; shaped = sv(q) * Math.exp(-((x - q.x) ** 2) / (2 * o.sig * o.sig)); }
        else {
          for (let i = 0; i < pts.length - 1; i++) {
            const a = pts[i], b = pts[i + 1];
            if (x >= a.x && x <= b.x) { const t2 = smooth(0, 1, (x - a.x) / (b.x - a.x)); shaped = lerp(sv(a), sv(b), t2); break; }
          }
        }
        for (const p of pts) {
          if (p.f > P.zone1) over = Math.max(over, Math.min(1, (p.f - P.zone1) * 30) * Math.exp(-((x - p.x) ** 2) / (2 * 0.025 * 0.025)));
        }
      }
      const z0 = -(o.limbR + 0.003);
      let padded = 0;
      for (const px of P.pads) padded = Math.max(padded, Math.exp(-((x - px) * (x - px)) / (2 * 0.028 * 0.028)));
      let hw = o.limbR + 0.003 + 0.0085 * padded + o.gap * (1 - shaped) - 0.004 * over;
      let flare = o.flare * (1 - shaped);
      let zr = z0 + o.depth + 0.006 * shaped;
      if (o.kind === 'leg' && o.segment === 'lower') {
        const hb = smooth(0.8, 0.9, t) * (1 - smooth(0.985, 1, t));
        hw += 0.006 * hb; zr += 0.014 * smooth(0.82, 0.97, t);
      }
      if (o.kind === 'arm' && o.segment === 'lower') hw *= 1 - 0.1 * smooth(0.3, 0.7, t);
      const rr = 0.03, dp = x + o.L / 2, dd = o.L / 2 - x;
      let k = 1;
      if (dp < rr) { const q = 1 - dp / rr; k = Math.min(k, Math.sqrt(Math.max(0, 1 - q * q))); }
      if (!o.plate && dd < rr) { const q = 1 - dd / rr; k = Math.min(k, Math.sqrt(Math.max(0, 1 - q * q))); }
      hw *= 0.62 + 0.38 * k;
      zr = z0 + (zr - z0) * (0.6 + 0.4 * k);
      flare *= k;
      return { hw, flare, zr, z0 };
    }
    // ring of the cross-section: inner (left→right), right rim, outer (right→left), left rim
    function ringPoints(x, out) {
      const th = G.o.th;
      const { hw, flare, zr, z0 } = profile(x);
      const hwTop = hw * (1 + flare);
      let n = 0;
      for (let k = 0; k <= K; k++) {
        const ph = -Math.PI / 2 + Math.PI * k / K, s = Math.sin(ph), c = Math.cos(ph);
        out[n++] = hw * s * (1 + flare * (1 - c)); out[n++] = z0 + (zr - z0) * (1 - c);
      }
      for (let r = 1; r <= RC; r++) {
        const a = Math.PI * r / (RC + 1);
        out[n++] = hwTop + th / 2 - (th / 2) * Math.cos(a); out[n++] = zr + (th / 2) * Math.sin(a);
      }
      for (let k = K; k >= 0; k--) {
        const ph = -Math.PI / 2 + Math.PI * k / K, s = Math.sin(ph), c = Math.cos(ph);
        const yi = hw * s * (1 + flare * (1 - c));
        out[n++] = yi + th * s; out[n++] = z0 + (zr - z0) * (1 - c) - th * c;
      }
      for (let r = 1; r <= RC; r++) {
        const a = Math.PI * r / (RC + 1);
        out[n++] = -(hwTop + th / 2) - (th / 2) * Math.cos(a); out[n++] = zr + (th / 2) * Math.sin(a);
      }
      return out;
    }

    function buildTrough() {
      const o = G.o;
      const pos = new Float32Array((NX + 1) * RING * 3), uv = new Float32Array((NX + 1) * RING * 2);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      const foam = [], shell = [];
      for (let i = 0; i < NX; i++) {
        for (let j = 0; j < RING; j++) {
          const isFoam = j < K, isShell = j >= K + RC + 1 && j <= 2 * K + RC;
          if (!isFoam && !isShell) continue;                         // rims → binding mesh
          const j2 = (j + 1) % RING;
          const a = i * RING + j, b = i * RING + j2, c = (i + 1) * RING + j, d = (i + 1) * RING + j2;
          (isFoam ? foam : shell).push(a, d, b, a, c, d);
        }
      }
      geo.setIndex(foam.concat(shell));
      geo.addGroup(0, foam.length, 0);
      geo.addGroup(foam.length, shell.length, 1);
      // liner print: u over the inner surface only (seam under the splint)
      const lt = linerTextures(o);
      const u0 = ((0 - JS + RING) % RING) / RING;
      [lt.map, lt.normal].forEach(t => { t.repeat.set(RING / K, 1); t.offset.set(-u0 * RING / K, 0); });
      if (M.foam.map) M.foam.map.dispose();
      if (M.foam.normalMap) M.foam.normalMap.dispose();
      M.foam.map = lt.map; M.foam.normalMap = lt.normal; M.foam.needsUpdate = true;
      const mesh = new THREE.Mesh(geo, [M.foam, M.shell]);
      mesh.renderOrder = 2;
      group.add(mesh);
      // woven binding over both rims (own vertices / UVs)
      const bgeo = new THREE.BufferGeometry();
      bgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array((NX + 1) * 2 * BV * 3), 3));
      const buv = new Float32Array((NX + 1) * 2 * BV * 2);
      const bi = [];
      for (let i = 0; i <= NX; i++) {
        for (let sd = 0; sd < 2; sd++) {
          for (let r = 0; r < BV; r++) {
            const q = ((i * 2 + sd) * BV + r) * 2;
            buv[q] = r / (BV - 1); buv[q + 1] = (o.L * i / NX) / 0.05;
            if (i < NX && r < BV - 1) {
              const a = (i * 2 + sd) * BV + r, b = a + 1, c = ((i + 1) * 2 + sd) * BV + r, d = c + 1;
              bi.push(a, d, b, a, c, d);
            }
          }
        }
      }
      bgeo.setAttribute('uv', new THREE.BufferAttribute(buv, 2));
      bgeo.setIndex(bi);
      bindT.map.repeat.set(1, 1); bindT.normal.repeat.set(1, 1);
      const bind = new THREE.Mesh(bgeo, M.bind);
      bind.renderOrder = 3;
      group.add(bind);
      // end caps (own vertices → flat normals)
      const capGeo = new THREE.BufferGeometry();
      capGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(2 * RING * 3), 3));
      const ci = [];
      for (let e = 0; e < 2; e++) {
        const base = e * RING, rimR = base + K + 1, outer = rimR + RC, rimL = outer + K + 1;
        for (let k = 0; k < K; k++) ci.push(base + k, base + k + 1, outer + (K - k), base + k + 1, outer + (K - k - 1), outer + (K - k));
        for (let r = 0; r < RC - 1; r++) ci.push(base + K, rimR + r, rimR + r + 1);
        ci.push(base + K, rimR + RC - 1, outer);
        ci.push(base, outer + K, rimL);
        for (let r = 0; r < RC - 1; r++) ci.push(base, rimL + r, rimL + r + 1);
      }
      capGeo.setIndex(ci);
      const caps = new THREE.Mesh(capGeo, M.cap);
      caps.renderOrder = 2;
      group.add(caps);
      G.trough = mesh; G.caps = caps; G.bind = bind;
      G.ringBuf = new Float32Array(RING * 2);
      fillTrough(true);
    }

    function fillTrough(first) {
      const o = G.o;
      const pos = G.trough.geometry.attributes.position.array, uv = G.trough.geometry.attributes.uv.array;
      const bpos = G.bind.geometry.attributes.position.array;
      const cap = G.caps.geometry.attributes.position.array;
      for (let i = 0; i <= NX; i++) {
        const x = -o.L / 2 + o.L * i / NX;
        ringPoints(x, G.ringBuf);
        for (let j = 0; j < RING; j++) {
          const p = (i * RING + j) * 3, q = (i * RING + j) * 2;
          pos[p] = x; pos[p + 1] = G.ringBuf[j * 2]; pos[p + 2] = G.ringBuf[j * 2 + 1];
          if (first) { uv[q] = ((j - JS + RING) % RING) / RING; uv[q + 1] = (x + o.L / 2) / o.L; }
          if (i === 0 || i === NX) {
            const e = i === 0 ? 0 : 1, cp = (e * RING + j) * 3;
            cap[cp] = x; cap[cp + 1] = pos[p + 1]; cap[cp + 2] = pos[p + 2];
          }
        }
        for (let sd = 0; sd < 2; sd++) {
          const rim = sd ? RIM_L : RIM_R;
          for (let r = 0; r < BV; r++) {
            const j = rim[r], b = ((i * 2 + sd) * BV + r) * 3;
            bpos[b] = x; bpos[b + 1] = G.ringBuf[j * 2]; bpos[b + 2] = G.ringBuf[j * 2 + 1] + 0.0004;
          }
        }
      }
      [G.trough, G.bind, G.caps].forEach(m => {
        m.geometry.attributes.position.needsUpdate = true;
        m.geometry.computeVertexNormals();
        m.geometry.computeBoundingSphere();
      });
      if (first) G.trough.geometry.attributes.uv.needsUpdate = true;
    }

    function roundedRect(w, h, r) {
      const s = new THREE.Shape();
      s.moveTo(-w / 2 + r, 0); s.lineTo(w / 2 - r, 0); s.quadraticCurveTo(w / 2, 0, w / 2, r);
      s.lineTo(w / 2, h - r); s.quadraticCurveTo(w / 2, h, w / 2 - r, h); s.lineTo(-w / 2 + r, h);
      s.quadraticCurveTo(-w / 2, h, -w / 2, h - r); s.lineTo(-w / 2, r); s.quadraticCurveTo(-w / 2, 0, -w / 2 + r, 0);
      return s;
    }
    const SWAP = new THREE.Matrix4().set(0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1);   // shape (x,y,extrude) → (y,z,x)

    function buildEnd() {
      const o = G.o;
      const z0 = -(o.limbR + 0.003), base = z0 - o.th;
      if (o.plate) {
        const w = o.width + 0.012, hgt = o.kind === 'leg' && o.segment === 'lower' ? 0.2 : 0.16;
        const g = new THREE.ExtrudeGeometry(roundedRect(w, hgt, 0.018), { depth: 0.012, bevelEnabled: true, bevelThickness: 0.003, bevelSize: 0.003, bevelSegments: 3, curveSegments: 6 });
        g.applyMatrix4(SWAP);
        const plate = new THREE.Mesh(g, M.shell);
        plate.position.set(o.L / 2 - 0.004, 0, base);
        plate.renderOrder = 3;
        group.add(plate);
        const pf = new THREE.Mesh(new THREE.BoxGeometry(0.012, w - 0.02, hgt - 0.03), M.plateFoam);
        pf.position.set(o.L / 2 - 0.01, 0, base + hgt / 2 + 0.006);
        pf.renderOrder = 3;
        group.add(pf);
        // heel-strap slot ribs and a lightening slot on the plate top edge
        for (const sgn of [-1, 1]) {
          const rib = new THREE.Mesh(new THREE.BoxGeometry(0.018, 0.022, 0.008), M.tab);
          rib.position.set(o.L / 2 + 0.002, sgn * (w / 2 - 0.02), base + hgt - 0.004);
          group.add(rib);
          const screw = new THREE.Mesh(new THREE.CylinderGeometry(0.0032, 0.0032, 0.003, 14), M.metal);
          screw.rotation.z = Math.PI / 2;
          screw.position.set(o.L / 2 + 0.0035, sgn * (w / 2 - 0.035), base + 0.03);
          group.add(screw);
        }
        const slot = new THREE.Mesh(new THREE.BoxGeometry(0.0125, w * 0.42, 0.012), M.dark);
        slot.position.set(o.L / 2 + 0.0005, 0, base + hgt - 0.022);
        group.add(slot);
      }
      if (o.kind === 'arm') {
        const hw = profile(o.L / 2 - 0.04).hw;
        const roll = new THREE.Mesh(new THREE.CylinderGeometry(0.019, 0.019, hw * 2 + 0.004, 28, 1), M.roll);
        roll.position.set(o.L / 2 - 0.045, 0, z0 + 0.019);
        roll.renderOrder = 3;
        group.add(roll);
        for (const sgn of [-1, 1]) {
          const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0195, 0.0016, 6, 28), M.dark);
          ring.rotation.x = Math.PI / 2;
          ring.position.set(o.L / 2 - 0.045, sgn * (hw - 0.004), z0 + 0.019);
          group.add(ring);
        }
      }
    }

    function buildPads() {
      const o = G.o;
      G.pads = o.sites.map(site => {
        const pair = new THREE.Group();
        for (const sgn of [-1, 1]) {
          const g = new THREE.CapsuleGeometry(0.0085, 0.04, 6, 14);
          g.rotateZ(Math.PI / 2);
          const m = new THREE.Mesh(g, M.pad);
          m.scale.set(1, 0.62, 1.9);
          m.position.set(0, sgn * (o.limbR + 0.0062), -(o.limbR + 0.003) + 0.026);
          m.renderOrder = 4;
          pair.add(m);
        }
        pair.position.x = site.x;
        pair.visible = false;
        group.add(pair);
        return pair;
      });
    }

    const SM = 34;
    function buildStraps() {
      const o = G.o;
      G.straps = o.strapX.map((x, si) => {
        const pos = new Float32Array(SM * 4 * 3), uv = new Float32Array(SM * 4 * 2);
        const idx = [];
        for (let i = 0; i < SM - 1; i++) {
          const a = i * 4, b = (i + 1) * 4;
          idx.push(a, b, a + 1, a + 1, b, b + 1);               // top
          idx.push(a + 2, a + 3, b + 2, a + 3, b + 3, b + 2);   // bottom
          idx.push(a, a + 2, b, a + 2, b + 2, b);               // edge -x
          idx.push(a + 1, b + 1, a + 3, a + 3, b + 1, b + 3);   // edge +x
        }
        for (let i = 0; i < SM; i++) {
          for (let k = 0; k < 4; k++) { uv[(i * 4 + k) * 2] = k % 2; uv[(i * 4 + k) * 2 + 1] = i / (SM - 1); }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
        geo.setIndex(idx);
        const mesh = new THREE.Mesh(geo, M.strap);
        mesh.renderOrder = 5;
        group.add(mesh);
        // anchor tab riveted on the near rim
        const tab = new THREE.Group();
        const tb = new THREE.Mesh(new THREE.BoxGeometry(o.strapW + 0.012, 0.014, 0.016), M.tab);
        tab.add(tb);
        for (const dx of [-1, 1]) {
          const rivet = new THREE.Mesh(new THREE.CylinderGeometry(0.0032, 0.0032, 0.004, 14), M.metal);
          rivet.rotation.x = Math.PI / 2; rivet.position.set(dx * o.strapW * 0.3, 0, 0.009);
          tab.add(rivet);
        }
        group.add(tab);
        // D-ring on the far rim (the strap passes through and folds back on its hook patch)
        const dring = new THREE.Group();
        const arc = new THREE.Mesh(new THREE.TorusGeometry(o.strapW * 0.56, 0.0023, 8, 26, Math.PI), M.metal);
        dring.add(arc);
        const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.0023, 0.0023, o.strapW * 1.12, 10), M.metal);
        bar.rotation.z = Math.PI / 2;
        dring.add(bar);
        dring.visible = false;
        group.add(dring);
        // numbered pull tab on the free end
        const nt = new THREE.Mesh(new THREE.BoxGeometry(o.strapW * 0.72, 0.022, 0.0032), [M.tab, M.tab, M.tab, M.tab, numMats[si % 3], M.tab]);
        nt.renderOrder = 6;
        group.add(nt);
        return { x, mesh, tab, dring, nt, key: '' };
      });
    }

    // strap centre line in the y-z plane: lying open on the ground → wrapped over the limb
    function strapPath(s, k, tension, out) {
      const o = G.o;
      const pr = profile(s.x);
      const hwTop = pr.hw * (1 + pr.flare);
      const side = o.anchorSide;
      const yA = side * (hwTop + o.th + 0.004);
      const ground = pr.z0 - o.th - 0.0015;
      const zTop = o.limbR + 0.0045 - tension * 0.006;
      const e = easeInOut(k);
      for (let i = 0; i < SM; i++) {
        const u = i / (SM - 1);
        // open: from the tab, down onto the ground, lying out to the side
        const oy = yA + side * (0.012 + u * 0.15), oz = ground + (pr.zr - ground) * Math.exp(-u * 26) + 0.0015;
        // wrapped: arch from the tab over the limb to the far rim
        const th = Math.PI * u;
        const wy = yA * Math.cos(th);
        const wz = pr.zr + (zTop - pr.zr) * Math.pow(Math.sin(th), 0.55) + 0.002;
        const lift = Math.sin(Math.PI * e) * 0.07 * u;
        out[i * 2] = lerp(oy, wy, e);
        out[i * 2 + 1] = lerp(oz, wz, e) + lift;
      }
      return { yA, zr: pr.zr, hwTop };
    }
    function fillStrap(s, st) {
      const o = G.o;
      const buf = G.pathBuf || (G.pathBuf = new Float32Array(SM * 2));
      const info = strapPath(s, st.k, st.tension, buf);
      const pos = s.mesh.geometry.attributes.position.array;
      const w2 = o.strapW / 2, h = 0.0028;
      for (let i = 0; i < SM; i++) {
        const i0 = Math.max(0, i - 1), i1 = Math.min(SM - 1, i + 1);
        let ty = buf[i1 * 2] - buf[i0 * 2], tz = buf[i1 * 2 + 1] - buf[i0 * 2 + 1];
        const tl = Math.hypot(ty, tz) || 1; ty /= tl; tz /= tl;
        let ny = -tz, nz = ty;
        if (nz < 0) { ny = -ny; nz = -nz; }
        const y = buf[i * 2], z = buf[i * 2 + 1];
        const p = i * 12;
        pos[p] = s.x - w2; pos[p + 1] = y; pos[p + 2] = z;
        pos[p + 3] = s.x + w2; pos[p + 4] = y; pos[p + 5] = z;
        pos[p + 6] = s.x - w2; pos[p + 7] = y - ny * h; pos[p + 8] = z - nz * h;
        pos[p + 9] = s.x + w2; pos[p + 10] = y - ny * h; pos[p + 11] = z - nz * h;
      }
      s.mesh.geometry.attributes.position.needsUpdate = true;
      s.mesh.geometry.computeVertexNormals();
      s.mesh.geometry.computeBoundingSphere();
      s.mesh.material = st.k > 0.3 ? M.strap : M.strapO;
      const side = o.anchorSide;
      s.tab.position.set(s.x, info.yA - side * 0.002, info.zr - 0.004);
      const wrapped = st.k >= 0.999;
      s.dring.visible = wrapped;
      s.dring.position.set(s.x, -info.yA - side * 0.002, info.zr + 0.0035);
      s.dring.rotation.set(0, 0, side > 0 ? Math.PI : 0);
      if (wrapped) {
        // tail folded back over the D-ring: numbered tab hangs just outside the far rim
        s.nt.position.set(s.x, -info.yA - side * (o.strapW * 0.56 + 0.012), info.zr - 0.002);
        s.nt.rotation.set(side * 0.42, 0, 0);
      } else {
        const ey = buf[(SM - 1) * 2], ez = buf[(SM - 1) * 2 + 1];
        s.nt.position.set(s.x, ey + side * 0.011, ez + 0.0018);
        s.nt.rotation.set(0, 0, 0);
      }
    }

    const api = {
      ok: true,
      // o = { kind, segment, L, width, depth, th, limbR, plate, sites:[{x}], strapX:[x], strapW, anchorSide, print:{} }
      build(o) {
        disposeGroup();
        const gap = Math.max(0.008, o.width / 2 - o.th - o.limbR - 0.003);
        const oo = Object.assign({ gap, flare: 0.34, sig: 0.04 }, o);
        const hw = oo.limbR + 0.003 + gap;
        oo.perim = Math.PI / 2 * Math.sqrt(2 * (hw * hw + oo.depth * oo.depth)) * 1.12;
        G = { o: oo, P: { points: [], pads: [], zone0: 0.72, zone1: 1.0 } };
        buildTrough();
        buildEnd();
        buildPads();
        buildStraps();
        G.shapeKey = '';
        dirty = true;
      },
      // per frame
      update(st) {
        if (!G) return;
        if (!st.visible) { if (group.visible) { group.visible = false; dirty = true; } return; }
        if (!group.visible) { group.visible = true; dirty = true; }
        const r1 = v => Math.round(v * 2) / 2;
        const pose = [r1(st.C.x), r1(st.C.y), Math.atan2(-st.s.y, st.s.x).toFixed(4), st.ppm.toFixed(2), st.opacity.toFixed(3), r1(st.limbA.x), r1(st.limbA.y), r1(st.limbB.x), r1(st.limbB.y), st.H].join(',');
        if (pose !== G.poseKey) {
          G.poseKey = pose; dirty = true;
          group.position.set(st.C.x, -st.C.y, 0);
          group.rotation.set(0, 0, Math.atan2(-st.s.y, st.s.x));
          group.scale.setScalar(st.ppm);
          FU.uLimbA.value.set(st.limbA.x, st.H - st.limbA.y);
          FU.uLimbB.value.set(st.limbB.x, st.H - st.limbB.y);
          FU.uLimbR.value = st.limbR;
          FU.uFade.value = st.fade;
          FU.uOpacity.value = st.opacity;
        }
        // shaping
        const P = G.P;
        P.points = st.points || [];
        P.zone0 = st.zone[0]; P.zone1 = st.zone[1];
        P.pads = (st.pads || []).map((p, i) => (p.on ? G.o.sites[i].x : null)).filter(x => x !== null);
        const sk = P.points.map(p => p.f.toFixed(3)).join(',') + '|' + P.pads.join(',');
        if (sk !== G.shapeKey) { G.shapeKey = sk; fillTrough(false); G.strapsStale = true; dirty = true; }
        // pads
        (G.pads || []).forEach((pair, i) => {
          const p = st.pads && st.pads[i];
          const vis = !!(p && p.on);
          const k = vis ? 1 + (p.pop || 0) * 0.35 : 1;
          if (pair.visible !== vis || pair.scale.x !== k) { pair.visible = vis; pair.scale.set(k, k, k); dirty = true; }
        });
        // straps
        (G.straps || []).forEach((s, i) => {
          const ss = st.straps && st.straps[i] ? st.straps[i] : { k: 0, tension: 0, show: false };
          const show = ss.show !== false;
          if (s.mesh.visible !== show) { s.mesh.visible = s.tab.visible = s.nt.visible = show; dirty = true; }
          if (!show) { s.dring.visible = false; return; }
          const kk = `${ss.k.toFixed(3)}|${(ss.tension || 0).toFixed(3)}`;
          if (kk !== s.key || G.strapsStale) { s.key = kk; fillStrap(s, ss); dirty = true; }
        });
        G.strapsStale = false;
      },
      render(W, H, fov) {
        if (R.domElement.width !== W || R.domElement.height !== H || fov !== lastFov) dirty = true;
        lastFov = fov;
        if (!dirty) return;
        dirty = false;
        if (R.domElement.width !== W || R.domElement.height !== H) R.setSize(W, H, false);
        const D = (H / 2) / Math.tan((fov * Math.PI / 180) / 2);
        cam.fov = fov; cam.aspect = W / H; cam.near = D * 0.2; cam.far = D * 3;
        cam.position.set(W / 2, -H / 2, D);
        cam.up.set(0, 1, 0);
        cam.lookAt(W / 2, -H / 2, 0);
        cam.updateProjectionMatrix();
        R.render(scene, cam);
      },
      clear() { R.clear(); dirty = true; if (G) G.poseKey = ''; },
      dispose() { disposeGroup(); G = null; R.clear(); },
    };
    return api;
  }

  /* ═════════════════════ BONE ILLUSTRATION (fracture card) ═════════════════════ */
  function boneSVG(kind, segment, frac, angle, displaced, open, labels) {
    const W = 300, H = 92, x0 = 26, x1 = 274, cy = 40;
    const fx = x0 + (x1 - x0) * clamp(frac, 0.2, 0.8);
    const ang = displaced ? clamp(angle || 8, 4, 28) : 0;
    const bones = [];
    if (kind === 'leg' && segment === 'lower') bones.push({ y: cy - 4, t: 9.5, cap: 15, capL: 13 }, { y: cy + 13, t: 3.6, cap: 6, capL: 6, thin: true });
    else if (kind === 'leg') bones.push({ y: cy, t: 11, cap: 16, capL: 17, head: true });
    else if (segment === 'lower') bones.push({ y: cy - 6, t: 5.4, cap: 9, capL: 8 }, { y: cy + 9, t: 5, cap: 8, capL: 10 });
    else bones.push({ y: cy, t: 8, cap: 13, capL: 12, head: true });
    const shaft = (b, a, z) => {
      // one long bone from a to z (x), with knobbly ends
      const t = b.t, y = b.y;
      return `M${a + b.capL} ${y - t} C${a + b.capL * 0.6} ${y - t - 2} ${a + 4} ${y - b.capL} ${a} ${y - b.capL * 0.55}
        C${a - 6} ${y - b.capL * 0.2} ${a - 6} ${y + b.capL * 0.2} ${a} ${y + b.capL * 0.55}
        C${a + 4} ${y + b.capL} ${a + b.capL * 0.6} ${y + t + 2} ${a + b.capL} ${y + t}
        L${z - b.cap} ${y + t} C${z - b.cap * 0.6} ${y + t + 2} ${z - 3} ${y + b.cap} ${z} ${y + b.cap * 0.6}
        C${z + 6} ${y + b.cap * 0.2} ${z + 6} ${y - b.cap * 0.2} ${z} ${y - b.cap * 0.6}
        C${z - 3} ${y - b.cap} ${z - b.cap * 0.6} ${y - t - 2} ${z - b.cap} ${y - t} Z`;
    };
    const zig = (y, t) => { let d = `M${fx - 2} ${y - t - 3}`; const n = 5; for (let i = 1; i <= n; i++) d += ` L${fx + (i % 2 ? 4 : -3)} ${y - t - 3 + (2 * t + 6) * i / n}`; return d; };
    let defs = `<defs>
      <linearGradient id="spb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4fbff"/><stop offset=".55" stop-color="#b9cfd8"/><stop offset="1" stop-color="#6f8893"/></linearGradient>
      <radialGradient id="spf" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="rgba(255,90,96,.75)"/><stop offset="1" stop-color="rgba(255,90,96,0)"/></radialGradient>
      <clipPath id="spL"><rect x="0" y="0" width="${fx}" height="${H}"/></clipPath>
      <clipPath id="spR"><rect x="${fx}" y="0" width="${W - fx}" height="${H}"/></clipPath>
      <pattern id="spg" width="10" height="10" patternUnits="userSpaceOnUse"><path d="M10 0H0V10" fill="none" stroke="rgba(120,200,210,.07)" stroke-width="1"/></pattern>
    </defs>`;
    let body = `<rect x="0" y="0" width="${W}" height="${H}" fill="url(#spg)"/>`;
    const glow = `<ellipse cx="${fx}" cy="${cy + 3}" rx="26" ry="30" fill="url(#spf)"/>`;
    bones.forEach(b => {
      const d = shaft(b, x0, x1);
      body += `<path d="${d}" clip-path="url(#spL)" fill="url(#spb)" stroke="rgba(220,245,255,.55)" stroke-width="1"/>`;
      body += `<g transform="rotate(${(-ang).toFixed(1)} ${fx} ${b.y}) translate(${displaced ? 2.5 : 1.5} ${displaced ? -3 : 0})"><path d="${d}" clip-path="url(#spR)" fill="url(#spb)" stroke="rgba(220,245,255,.55)" stroke-width="1"/></g>`;
      body += `<path d="${zig(b.y, b.t)}" fill="none" stroke="#ff6b70" stroke-width="${b.thin ? 1.2 : 1.6}" stroke-linejoin="round"/>`;
      body += `<path d="M${x0 + b.capL + 8} ${b.y - b.t * 0.35}H${fx - 8}M${fx + 10} ${b.y - b.t * 0.35}H${x1 - b.cap - 6}" stroke="rgba(255,255,255,.35)" stroke-width="${b.thin ? 0.6 : 1}" stroke-linecap="round"/>`;
    });
    if (open) body += `<path d="M${fx - 9} ${cy - 22}q9 -7 18 0" fill="none" stroke="#ff6b70" stroke-width="2.2" stroke-linecap="round"/><circle cx="${fx + 12}" cy="${cy - 24}" r="2" fill="#ff6b70"/>`;
    // angle readout
    if (ang) {
      const r = 30, a1 = ang * Math.PI / 180;
      body += `<path d="M${fx + r} ${cy - 4}A${r} ${r} 0 0 0 ${(fx + r * Math.cos(a1)).toFixed(1)} ${(cy - 4 - r * Math.sin(a1)).toFixed(1)}" fill="none" stroke="#f3c35a" stroke-width="1.4" stroke-dasharray="3 2"/>`;
      body += `<line x1="${fx}" y1="${cy - 4}" x2="${fx + r + 10}" y2="${cy - 4}" stroke="rgba(243,195,90,.5)" stroke-width="1" stroke-dasharray="2 2"/>`;
    }
    body += `<text x="${x0 - 4}" y="${H - 6}" class="bj">${esc(labels[0] || '')}</text><text x="${x1 + 4}" y="${H - 6}" class="bj" text-anchor="end">${esc(labels[1] || '')}</text>`;
    body += `<line x1="${fx}" y1="${H - 18}" x2="${fx}" y2="${H - 10}" stroke="#ff6b70" stroke-width="1.4"/>`;
    return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${defs}${glow}${body}</svg>`;
  }

  /* ═══════════════════════════ APP ═══════════════════════════ */
  const A = {
    escClose: false,
    camInput: true,

    init(el) {
      this.el = el;
      el.innerHTML = `
        <canvas class="sp-cv sp-under"></canvas>
        <canvas class="sp-cv sp-gl"></canvas>
        <canvas class="sp-cv sp-over"></canvas>
        <div class="sp-tags"></div>
        <div class="sp-frac nza-hud solid" hidden></div>
        <div class="sp-cms nza-hud solid" hidden></div>
        <div class="sp-res nza-hud solid" hidden></div>
        <div class="sp-hint" hidden></div>
        <div class="sp-hud nza-hud solid" hidden></div>`;
      this.under = el.querySelector('.sp-under');
      this.glc = el.querySelector('.sp-gl');
      this.over = el.querySelector('.sp-over');
      this.uc = this.under.getContext('2d');
      this.oc = this.over.getContext('2d');
      this.tagsEl = el.querySelector('.sp-tags');
      this.fracEl = el.querySelector('.sp-frac');
      this.cmsEl = el.querySelector('.sp-cms');
      this.resEl = el.querySelector('.sp-res');
      this.hintEl = el.querySelector('.sp-hint');
      this.hudEl = el.querySelector('.sp-hud');
      this.anc = {};
      this.tags = {};
      this.shift = false;
      this.held = new Set();
      this.gl = undefined;
      NZA.ui.Anchors(APP).on(map => { this.anc = map || {}; });

      window.addEventListener('keydown', e => { if (e.key === 'Shift') this.shift = true; });
      window.addEventListener('keyup', e => { if (e.key === 'Shift') this.shift = false; });
      window.addEventListener('blur', () => { this.held.clear(); this.shift = false; this.pointerUp(); });
      window.addEventListener('mousedown', e => this.pointerDown(e));
      window.addEventListener('mousemove', e => this.pointerMove(e));
      window.addEventListener('mouseup', e => { if (e.button === 0) this.pointerUp(e); });
      this.loop = this.loop.bind(this);
      this.hudTick = this.hudTick.bind(this);
      this.reduced = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    },

    open(d) {
      LOC = Object.assign(LOC, d.locale || {});
      if (d.mode === 'hud') { this.hudShow(d.hud || {}); return; }
      this.procStart(d);
    },

    close() {
      this.procStop();
      this.hudHide();
    },

    msg: {
      result(o) { A.showResult(o || {}); },
      hud(d) { A.hudShow(d || {}); },
      hudOff() { A.hudHide(); },
      procEnd() { A.procStop(); },
      error(d) { if (A.pp) A.pp.flash('bad', (d && d.msg) || T('err', 'Something went wrong'), 3200); },
    },

    keys: {},
    keysUp: {},

    /* ═════════════════════ PROCEDURE ═════════════════════ */
    procStart(d) {
      this.procStop();
      this.d = d;
      this.tune = Object.assign({}, DEF_TUNE, d.tune || {});
      this.K = Object.assign({}, DEF_KEYS, d.keys || {});
      const kind = d.device === 'arm' || d.limb === 'arm' ? 'arm' : 'leg';
      const segment = d.segment === 'upper' ? 'upper' : 'lower';
      this.kind = kind; this.segment = segment;
      const size = Object.assign({}, SIZE[kind], d.size || {});
      this.size = size;
      const ext = EXT[kind][segment];
      this.extP = ext[0]; this.extD = ext[1];
      this.segLen = Math.max(0.12, Number(d.segLen) || (kind === 'leg' ? 0.43 : 0.27));
      this.Ls = this.segLen + this.extP + this.extD;
      this.fov = Number(d.fov) || 50;
      const sp = this.tune.shapePoints;
      const nPts = clamp(Math.round(Number(typeof sp === 'object' && sp ? sp[kind] : sp) || (kind === 'leg' ? 6 : 5)), 3, 9);
      const L = this.Ls;
      const xJp = -L / 2 + this.extP, xJd = L / 2 - this.extD;          // joints in splint coordinates
      const frac = clamp(Number(d.fracture && d.fracture.at) || 0.5, 0.25, 0.75);
      const xFr = xJp + (xJd - xJp) * frac;
      const pts = [];
      for (let i = 0; i < nPts; i++) {
        const x = (xJp - this.extP * 0.45) + ((xJd + this.extD * 0.3) - (xJp - this.extP * 0.45)) * (i / (nPts - 1));
        pts.push({ x, f: 0, done: false, tight: false, pop: 0 });
      }
      // straps: one past each joint, one on the side of the break with more room
      const sA = xJp - this.extP * 0.45, sC = xJd - 0.015;
      const room1 = xFr - xJp, room2 = xJd - xFr;
      const sB = room1 > room2 ? xFr - Math.min(0.11, room1 * 0.55) : xFr + Math.min(0.11, room2 * 0.55);
      const S = {
        step: 1, active: true, t0: performance.now(), tool: 'splint',
        pose: { cu: 0, cv: 0, phi: 0 }, pose0: null, intro: 0,
        drag: null, alignHold: 0, locked: false, lockAnim: null, resets: 0, moved: false,
        aligned: { p: false, d: false }, err: { p: 1, d: 1, a: 90 }, snap: { p: 0, d: 0 },
        xFr, frac,
        sites: [{ key: 'prox', x: xJp, padded: false, pop: 0 }, { key: 'dist', x: xJd, padded: false, pop: 0 }],
        points: pts, press: -1,
        straps: [sA, sB, sC].map((x, i) => ({ i, x, state: 'open', k: 0, tension: 0, ph: 0, quality: 0, locks: 0, tight: false, loose: false })),
        sweeping: -1,
        cms: { state: 'hidden', checks: 0, t: 0, shown: -1, rows: null, fixed: false, tight: false },
        tightEver: 0, s1: 0, s2: 0, s3: 0, finished: false, result: null, side: 1,
      };
      this.S = S;
      this.held.clear();
      this.wireKeys();
      [this.under, this.glc, this.over].forEach(c => c.classList.add('on'));
      this.cmsEl.hidden = true; this.resEl.hidden = true; this.hintEl.hidden = true;
      this.hudEl.classList.add('away');
      this.tagsEl.innerHTML = ''; this.tags = {};
      this.renderFracture();

      if (this.gl === undefined) this.gl = SplintGL(this.glc);
      this.glBuilt = false;

      this.pp = NZA.ui.ProcPanel(this.el, {
        step: 1, total: 3, tag: `${T('tag', 'Splinting')} · ${d.regionLabel || ''}`,
        steps: [T('st1', 'Lay the splint'), T('st2', 'Pad & shape'), T('st3', 'Strap & check')],
        title: '', text: '', stats: [], tools: this.toolsFor(), hints: [],
        abort: { label: T('abort', 'Hold to stop'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(),
        onTool: k => this.selectTool(k),
      });
      this.enterStep(1);
      if (d.open) setTimeout(() => this.pp && this.S === S && S.step === 1 && this.pp.flash('warn', d.dressed ? T('open_dressed', 'Open fracture, already covered. Keep the dressing clean under the splint.') : T('open_warn', 'Open fracture: the bone broke the skin. Cover it before you strap over it.'), 5200), 600);
      else if (d.fracture && d.fracture.displaced) setTimeout(() => this.pp && this.S === S && S.step === 1 && this.pp.flash('warn', T('displaced', 'Displaced %s°. Splint it where it lies - it is set in hospital.', Math.round(d.fracture.angle || 0)), 4600), 600);
      if (!this.raf) { this.last = 0; this.raf = requestAnimationFrame(this.loop); }
    },

    procStop() {
      if (this.S) this.S.active = false;
      this.S = null;
      this.held.clear();
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.raf) { cancelAnimationFrame(this.raf); this.raf = 0; }
      if (this.trace) { this.trace.stop(); this.trace = null; }
      [this.under, this.glc, this.over].forEach(c => c.classList.remove('on'));
      [this.uc, this.oc].forEach(c => { c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, c.canvas.width, c.canvas.height); });
      this._shKey = '';
      if (this.gl) this.gl.clear();
      this.tagsEl.innerHTML = ''; this.tags = {};
      this.cmsEl.hidden = true; this.resEl.hidden = true; this.hintEl.hidden = true; this.fracEl.hidden = true;
      this.hudEl.classList.remove('away');
      this.keys = {}; this.keysUp = {};
    },

    wireKeys() {
      const K = this.K;
      const down = name => e => { if (!this.S || this.S.finished) return false; this.held.add(name); this.S.moved = true; return true; };
      const up = name => () => { this.held.delete(name); return true; };
      const tool = e => !!(this.pp && !e.repeat && this.pp.key(e));
      this.keys = {
        [K.rotateLeft]: down('rotL'), [K.rotateRight]: down('rotR'),
        ArrowUp: down('up'), ArrowDown: down('down'), ArrowLeft: down('left'), ArrowRight: down('right'),
        [K.reset]: e => { if (!e.repeat) this.resetSplint(); },
        [K.set]: e => { if (!e.repeat) this.setKey(); },
        1: tool, 2: tool, 3: tool, 4: tool, 5: tool,
        Enter: e => !!(this.pp && this.pp.key(e)),
      };
      this.keysUp = {
        [K.rotateLeft]: up('rotL'), [K.rotateRight]: up('rotR'),
        ArrowUp: up('up'), ArrowDown: up('down'), ArrowLeft: up('left'), ArrowRight: up('right'),
      };
    },

    toolsFor() {
      const S = this.S;
      const step = S ? S.step : 1, tool = S ? S.tool : 'splint';
      const st = (n, id) => {
        if (S && S.finished) return 'done';
        if (n < step) return 'done';
        if (n > step) return 'locked';
        if (id === tool) return 'active';
        if (step === 2 && id === 'pad' && S && S.sites.every(s => s.padded)) return 'done';
        if (step === 3 && id === 'strap' && S && S.straps.every(s => s.state === 'locked')) return 'done';
        if (step === 3 && id === 'cms' && S && S.cms.state === 'hidden') return 'locked';
        return '';
      };
      const pads = S ? S.sites.filter(s => s.padded).length : 0;
      const straps = S ? S.straps.filter(s => s.state === 'locked').length : 0;
      return [
        { key: '1', id: 'splint', label: this.d && this.d.deviceModel ? `${T('tool_splint', 'Splint')} ${this.d.deviceModel}` : T('tool_splint', 'Splint'), sub: T('tool_splint_sub', 'Lay & align'), icon: 'splint', state: st(1, 'splint') },
        { key: '2', id: 'pad', label: T('tool_pad', 'Padding'), sub: `${pads}/2`, icon: 'gauze', state: st(2, 'pad') },
        { key: '3', id: 'shape', label: T('tool_shape', 'Shape'), sub: T('tool_shape_sub', 'Press & hold'), icon: 'hand', state: st(2, 'shape') },
        { key: '4', id: 'strap', label: T('tool_strap', 'Straps'), sub: `${straps}/3`, icon: 'cuff', state: st(3, 'strap') },
        { key: '5', id: 'cms', label: T('tool_cms', 'Distal check'), sub: T('tool_cms_sub', 'Pulse · move · feel'), icon: 'pulse', state: st(3, 'cms') },
      ];
    },
    refreshTools() { if (this.pp) this.pp.set({ tools: this.toolsFor() }); },

    selectTool(key) {
      const S = this.S;
      if (!S || S.finished) return;
      const map = { 1: 'splint', 2: 'pad', 3: 'shape', 4: 'strap', 5: 'cms' };
      const id = map[key];
      if (!id) return;
      if (S.step === 2 && (id === 'pad' || id === 'shape')) {
        S.tool = id; NZA.audio.click(720); this.enterStep(2, true);
      } else if (S.step === 3 && id === 'cms') {
        if (S.cms.state === 'ready' || S.cms.state === 'bad') this.cmsCheck();
        else this.pp.flash('warn', T('cms_first', 'Secure all three straps first.'), 1800);
      } else if (S.step === 3 && id === 'strap') {
        S.tool = 'strap'; this.refreshTools();
      }
    },

    hintsFor(step) {
      const K = this.K;
      if (step === 1) {
        return [
          { keys: [T('k_drag', 'Drag')], label: T('h_slide', 'Slide') },
          { keys: [keyLabel(K.rotateLeft), keyLabel(K.rotateRight)], label: T('h_turn', 'Turn') },
          { keys: ['←', '→', '↑', '↓'], label: T('h_nudge', 'Nudge') },
          { keys: ['Shift'], label: T('h_fine', 'Fine') },
          { keys: [keyLabel(K.set)], label: T('h_set', 'Set') },
          { keys: [keyLabel(K.reset)], label: T('h_reset', 'Start over') },
          { keys: [T('k_rdrag', 'Right-drag')], label: T('h_view', 'Rotate view') },
        ];
      }
      if (step === 2) {
        return [
          { keys: ['2'], label: T('h_pad', 'Padding') },
          { keys: ['3'], label: T('h_shape', 'Shape') },
          { keys: [T('k_hold', 'Hold')], label: T('h_press', 'Press the wall in') },
          { keys: ['Shift'], label: T('h_gentle', 'Gentle') },
          { keys: [T('k_rdrag', 'Right-drag')], label: T('h_view', 'Rotate view') },
        ];
      }
      return [
        { keys: [T('k_click', 'Click')], label: T('h_wrap', 'Wrap strap') },
        { keys: [T('k_click', 'Click'), keyLabel(K.set)], label: T('h_cinch', 'Cinch') },
        { keys: ['5'], label: T('h_check', 'Distal check') },
        { keys: [T('k_rdrag', 'Right-drag')], label: T('h_view', 'Rotate view') },
      ];
    },

    enterStep(n, keepFlash) {
      const S = this.S, d = this.d;
      if (!S) return;
      S.step = n;
      if (!keepFlash) {
        if (n === 1) S.tool = 'splint';
        if (n === 2) S.tool = 'pad';
        if (n === 3) S.tool = 'strap';
      }
      const J = d.joints || {};
      const prox = J.prox || T(`j_${J.proxKey || 'prox'}`, 'the upper joint'), dist = J.dist || T(`j_${J.distKey || 'dist'}`, 'the lower joint');
      const cmsName = J.cms || (this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers'));
      let title = '', text = '';
      if (n === 1) {
        title = T('s1_title', 'Lay the splint');
        text = T('s1_text', 'Slide the splint under the **%s** so it reaches past the **%s** and the **%s**. {%s} {%s} turn it, the arrows nudge it.', (d.regionLabel || '').toLowerCase(), prox.toLowerCase(), dist.toLowerCase(), keyLabel(this.K.rotateLeft), keyLabel(this.K.rotateRight));
      } else if (n === 2) {
        title = S.tool === 'pad' ? T('s2_title_pad', 'Pad the bony points') : T('s2_title_shape', 'Shape it to the limb');
        text = S.tool === 'pad'
          ? T('s2_text_pad', 'Click the marked spots at the **%s** and **%s** to pad them, so nothing hard presses on bone.', prox.toLowerCase(), dist.toLowerCase())
          : T('s2_text_shape', 'Press and hold each point until the walls close on the limb. Let go **inside the band** - squeezing past it leaves a pressure point.');
      } else {
        const allLocked = S.straps.every(s => s.state === 'locked');
        if (allLocked && S.cms.state === 'bad') {
          title = T('s3_title_bad', 'Loosen the tight strap');
          text = T('s3_text_bad', 'Click the strap marked in red to loosen it, cinch it again **inside the band**, then check the **%s** again.', cmsName);
        } else {
          title = allLocked ? T('s3_title_cms', 'Check below the splint') : T('s3_title', 'Strap it in place');
          text = allLocked
            ? T('s3_text_cms', 'Click the **%s** to check circulation, movement and feeling below the splint.', cmsName)
            : T('s3_text', 'Click a strap to wrap it over the limb, then click again (or {%s}) when the needle sits **in the band**. Keep straps off the break.', keyLabel(this.K.set));
        }
      }
      this.pp.set({ step: n, title, text, tools: this.toolsFor(), hints: this.hintsFor(n) });
      this.updateReadout(true);
    },

    // left-column readout: dial + instrument list
    updateReadout(force) {
      const S = this.S, d = this.d;
      if (!S || !this.pp) return;
      const now = performance.now();
      if (!force && this._ro && now - this._ro < 90) return;
      this._ro = now;
      const J = d.joints || {};
      const prox = J.prox || T('j_prox', 'Upper end'), dist = J.dist || T('j_dist', 'Lower end');
      const t = this.tune;
      let wide, stats;
      if (S.step === 1) {
        const fit = this.fitPct();
        const ok = S.aligned.p && S.aligned.d;
        wide = { label: T('fit', 'Fit'), value: fit, unit: '%', tone: ok ? 'teal' : '', meter: { value: fit / 100, zone: [0.82, 1], tone: ok ? '' : 'white' },
                 caption: ok ? T('cap_hold', 'Hold still to set') : T('cap_fit', 'Reach past both joints'), captionTone: ok ? 'teal' : '' };
        const endVal = (okE, e) => (okE ? T('seated', 'Seated') : `${mm(e)} mm`);
        stats = [
          { id: 'p', label: `${prox}`, value: endVal(S.aligned.p, S.err.p), small: S.aligned.p, tone: S.aligned.p ? 'teal' : '' },
          { id: 'd', label: `${dist}`, value: endVal(S.aligned.d, S.err.d), small: S.aligned.d, tone: S.aligned.d ? 'teal' : '' },
          { id: 'a', label: T('angle', 'Angle'), value: Math.round(S.err.a), unit: '°', tone: S.err.a > t.angleTolerance ? 'amber' : '' },
        ];
      } else if (S.step === 2) {
        const fit = this.contactPct();
        const shaped = S.points.filter(p => p.done).length, pads = S.sites.filter(s => s.padded).length, press = S.points.filter(p => p.tight).length;
        const cur = S.press >= 0 ? S.points[S.press] : null;
        wide = cur
          ? { label: T('pressure', 'Pressure'), value: Math.round(Math.min(1.1, cur.f) * 100), unit: '%', tone: cur.f > t.shapeZone[1] ? 'amber' : cur.f >= t.shapeZone[0] ? 'teal' : '', meter: { value: Math.min(1, cur.f / 1.1), zone: [t.shapeZone[0] / 1.1, t.shapeZone[1] / 1.1], tone: cur.f > t.shapeZone[1] ? 'amber' : '' }, caption: cur.f >= t.shapeZone[0] ? T('cap_release', 'Let go now') : T('cap_press', 'Keep pressing'), captionTone: cur.f >= t.shapeZone[0] ? 'teal' : '' }
          : { label: T('contact', 'Contact'), value: fit, unit: '%', tone: fit >= 100 ? 'teal' : '', meter: { value: fit / 100, zone: [0.9, 1] }, caption: T('cap_contact', 'Walls against the limb'), captionTone: '' };
        stats = [
          { id: 'pad', label: T('padding', 'Padding'), value: pads, unit: '/2', tone: pads === 2 ? 'teal' : '' },
          { id: 'sh', label: T('shaped', 'Shaped'), value: shaped, unit: `/${S.points.length}`, tone: shaped === S.points.length ? 'teal' : '' },
          { id: 'pr', label: T('pressure_pts', 'Pressure points'), value: press, tone: press ? 'amber' : '' },
        ];
      } else {
        const locked = S.straps.filter(s => s.state === 'locked').length;
        const sw = S.sweeping >= 0 ? S.straps[S.sweeping] : null;
        const z = t.strapZone;
        if (sw && sw.state === 'sweep') {
          const inZ = sw.tension >= z[0] && sw.tension <= z[1];
          wide = { label: T('tension', 'Tension'), value: Math.round(sw.tension * 100), unit: '%', tone: sw.tension > t.strapTight ? 'red' : inZ ? 'teal' : '',
                   meter: { value: sw.tension, zone: z, mark: sw.tension, noFill: false, tone: sw.tension > t.strapTight ? 'red' : inZ ? '' : 'white' },
                   caption: inZ ? T('cap_cinch', 'Cinch now') : sw.tension > t.strapTight ? T('cap_tight', 'Too tight') : T('cap_wait', 'Wait for the band'), captionTone: inZ ? 'teal' : sw.tension > t.strapTight ? 'red' : '' };
        } else {
          const cmsTone = S.cms.state === 'ok' ? 'teal' : S.cms.state === 'bad' ? 'red' : '';
          wide = { label: T('straps', 'Straps'), value: `${locked}/3`, tone: locked === 3 ? 'teal' : '', meter: { value: locked / 3, tone: locked === 3 ? '' : 'white' },
                   caption: locked === 3 ? (S.cms.state === 'bad' ? T('cap_loosen', 'Loosen the tight strap') : T('cap_checknow', 'Check below the splint')) : T('cap_strap', 'Wrap and cinch'), captionTone: locked === 3 ? cmsTone || 'teal' : '' };
        }
        const cmsTxt = { hidden: T('cms_wait', 'After straps'), ready: T('cms_ready', 'Not checked'), checking: T('cms_checking', 'Checking…'), ok: T('cms_ok', 'Intact'), bad: T('cms_bad', 'Cut off') }[S.cms.state];
        const last = S.straps.filter(s => s.state === 'locked').slice(-1)[0];
        stats = [
          { id: 'st', label: T('straps', 'Straps'), value: locked, unit: '/3', tone: locked === 3 ? 'teal' : '' },
          { id: 'tn', label: T('last_tension', 'Last tension'), value: last ? Math.round(last.tension * 100) : '--', unit: last ? '%' : '', tone: last ? (last.tight ? 'red' : last.loose ? 'amber' : 'teal') : '' },
          { id: 'cms', label: T('cms', 'Distal check'), value: cmsTxt, small: true, tone: S.cms.state === 'ok' ? 'teal' : S.cms.state === 'bad' ? 'red' : '' },
        ];
      }
      this.pp.set({ wide, stats });
    },
    fitPct() {
      const S = this.S, tol = this.tune.tolerance;
      const e = (Math.min(S.err.p, tol * 6) + Math.min(S.err.d, tol * 6)) / 2;
      return Math.round(clamp(100 - (e / (tol * 6)) * 100 - Math.max(0, S.err.a - 2) * 1.2, 0, 100));
    },
    contactPct() {
      const S = this.S, z0 = this.tune.shapeZone[0];
      return Math.round(100 * S.points.reduce((a, p) => a + Math.min(1, p.f / z0), 0) / S.points.length);
    },

    abort() {
      if (!this.S || this.S.finished) return;
      NZA.post(`${APP}:abort`, {});
      if (!NZA.inGame) { NZA.toast({ title: T('title', 'Splint'), message: T('aborted', 'Splinting stopped'), type: 'error' }); NZA.close(APP); }
    },

    /* ─────────────── fracture card (top-left) ─────────────── */
    renderFracture() {
      const d = this.d, f = d.fracture || {};
      const J = d.joints || {};
      const sev = clamp(Number(d.severity) || 2, 1, 4);
      const pain = clamp(Math.round((Number(d.pain) || 0) / 10), 0, 10);
      const pulseTone = d.pulse === 'absent' ? 'red' : d.pulse === 'weak' ? 'amber' : 'teal';
      const pulseTxt = d.pulse === 'absent' ? T('p_absent', 'Absent') : d.pulse === 'weak' ? T('p_weak', 'Weak') : T('p_present', 'Present');
      const chips = [`<span class="chipx sm ${f.kind === 'open' ? 'red' : ''}">${esc(f.kindLabel || T('closed', 'Closed'))}</span>`];
      if (f.displaced) chips.push(`<span class="chipx sm amber">${esc(T('displaced_chip', 'Displaced %s°', Math.round(f.angle || 0)))}</span>`);
      else chips.push(`<span class="chipx sm teal">${esc(T('aligned_chip', 'In line'))}</span>`);
      chips.push(`<span class="chipx sm">${esc(T('sev', 'Severity %s/4', sev))}</span>`);
      const devLen = Math.round(this.Ls * 100);
      this.fracEl.innerHTML = `
        <div class="fh"><span class="k">${icon('bone')}${esc(T('fracture', 'Fracture'))}</span><span class="reg">${esc(d.regionLabel || '')}</span></div>
        <div class="ft">${esc(f.boneLabel || T('long_bone', 'Long bone'))}</div>
        <div class="fc">${chips.join('')}</div>
        <div class="bone">${boneSVG(this.kind, this.segment, this.S ? this.S.frac : 0.5, f.angle, !!f.displaced, f.kind === 'open', [J.prox || '', J.dist || ''])}</div>
        <div class="rows">
          <div class="r"><span>${esc(T('pre_pulse', 'Pulse below'))}</span><b class="${pulseTone}">${esc(pulseTxt)}</b></div>
          <div class="r"><span>${esc(T('pain', 'Pain'))}</span><span class="pbar"><i style="width:${pain * 10}%"></i></span><b>${pain}<small>/10</small></b></div>
          <div class="r"><span>${esc(T('device', 'Device'))}</span><b>${esc(d.deviceLabel || '')}<small> · ${esc(d.deviceModel || '')} · ${devLen} cm</small></b></div>
        </div>`;
      this.fracEl.hidden = false;
    },

    /* ─────────────── limb frame & splint geometry ─────────────── */
    frame() {
      const a = this.anc || {}, W = this.over.width, H = this.over.height;
      const pr = a.prox, di = a.dist;
      if (!pr || !di || pr.visible === false || di.visible === false || !W) return null;
      const P = v(pr.x * W, pr.y * H), D = v(di.x * W, di.y * H);
      const ax = sub(D, P), L = len(ax);
      if (L < 12) return null;
      const u = mul(ax, 1 / L), n = perp(u);
      const ppm = L / this.segLen;
      const Tp = sub(P, mul(u, this.extP * ppm)), Td = add(D, mul(u, this.extD * ppm));
      const more = LIMB_MORE[this.kind][this.segment];
      return { P, D, u, n, L, ppm, Tp, Td, M: mul(add(Tp, Td), 0.5), limbA: sub(P, mul(u, more[0] * ppm)), limbB: add(D, mul(u, more[1] * ppm)) };
    },
    geom(f, pose) {
      const s = rotv(f.u, pose.phi), m = perp(s);
      const C = add(f.M, add(mul(f.u, pose.cu * f.ppm), mul(f.n, pose.cv * f.ppm)));
      const H = this.Ls / 2;
      return { C, s, m, H, ppm: f.ppm, Sp: sub(C, mul(s, H * f.ppm)), Sd: add(C, mul(s, H * f.ppm)) };
    },
    // splint-local metres ↔ screen px
    local(g, p) { const r = sub(p, g.C); return v(dot(r, g.s) / g.ppm, dot(r, g.m) / g.ppm); },
    world(g, x, y) { return add(g.C, add(mul(g.s, x * g.ppm), mul(g.m, y * g.ppm))); },
    toPose(f, C, phi) { const r = sub(C, f.M); return { cu: dot(r, f.u) / f.ppm, cv: dot(r, f.n) / f.ppm, phi }; },

    // which side of the limb is away from the body (+1 = +n)
    bodySide(f) {
      const core = this.anc.core;
      if (core && core.visible !== false) {
        const c = v(core.x * this.over.width, core.y * this.over.height);
        return dot(sub(c, f.M), f.n) > 0 ? -1 : 1;
      }
      return 1;
    },
    // the splint starts lying beside the limb - on the free side (away from the body) unless that
    // side runs into the HUD columns or off screen
    initialPose(f) {
      const away = this.bodySide(f);
      const W = this.over.width, H = this.over.height, Z = H / 1080;
      const safe = { x0: 450 * Z, x1: W - 330 * Z, y0: 30 * Z, y1: H - 30 * Z };
      const pose = sd => ({ cu: 0.03, cv: sd * (this.size.width * 1.3 + 0.03), phi: sd * 0.14 });
      const overflow = p => {
        const g = this.geom(f, p);
        const hl = g.H * f.ppm, hw = (this.size.width / 2 + 0.17) * f.ppm;
        const ex = Math.abs(g.s.x) * hl + Math.abs(g.m.x) * hw, ey = Math.abs(g.s.y) * hl + Math.abs(g.m.y) * hw;
        return Math.max(0, safe.x0 - (g.C.x - ex)) + Math.max(0, g.C.x + ex - safe.x1) + Math.max(0, safe.y0 - (g.C.y - ey)) + Math.max(0, g.C.y + ey - safe.y1);
      };
      const a = pose(away), b = pose(-away);
      return overflow(b) + 40 * Z < overflow(a) ? b : a;
    },

    resetSplint() {
      const S = this.S;
      if (!S || S.step !== 1 || S.locked) return;
      const f = this.frame();
      if (!f) return;
      S.pose = this.initialPose(f); S.pose0 = Object.assign({}, S.pose);
      S.resets += 1; S.alignHold = 0; S.intro = performance.now();
      NZA.audio.noise(160, { vol: 0.05, lp: 1400, hp: 300 });
    },

    setKey() {
      const S = this.S;
      if (!S || S.finished) return;
      if (S.step === 1) {
        if (S.locked) return;
        if (S.aligned.p && S.aligned.d) this.lockSplint();
        else { this.pp.flash('warn', T('not_aligned', 'Both ends must sit past their joints first.'), 2000); NZA.audio.click(260); }
      } else if (S.step === 3 && S.sweeping >= 0 && S.straps[S.sweeping].state === 'sweep') {
        this.strapClick(S.sweeping);
      }
    },

    lockSplint() {
      const S = this.S, t = this.tune;
      const e = (S.err.p + S.err.d) / 2;
      S.s1 = Math.round(clamp(100 - (e / t.tolerance) * 22 - Math.max(0, S.err.a - 2) * 1.6 - Math.max(0, S.resets - 1) * 4, 35, 100));
      S.locked = true;
      S.lockAnim = { from: Object.assign({}, S.pose), t0: performance.now() };
      NZA.audio.noise(140, { vol: 0.12, lp: 420, hp: 40, attack: 0.02, release: 0.5 });
      NZA.audio.success();
      this.pp.flash('ok', T('set_ok', 'Splint set - it holds the joint above and below the break.'), 2400);
      setTimeout(() => { if (this.S === S) { S.pose = { cu: 0, cv: 0, phi: 0 }; this.enterStep(2); this.refreshTools(); } }, 700);
    },

    /* ─────────────── pointer ─────────────── */
    px(e) { return v(e.clientX / window.innerWidth * this.over.width, e.clientY / window.innerHeight * this.over.height); },
    overUi(e) { return !!(e.target && e.target.closest && e.target.closest('.pp-col,.pp-belt,.sp-res,.sp-hud,.sp-frac,.sp-cms')); },

    pointerDown(e) {
      const S = this.S;
      if (!S || !S.active || S.finished || e.button !== 0 || this.overUi(e)) return;
      const f = this.frame();
      if (!f) return;
      const p = this.px(e);
      const g = this.geom(f, S.pose);
      const l = this.local(g, p);
      if (S.step === 1 && !S.locked) {
        if (Math.abs(l.x) <= g.H + 0.03 && Math.abs(l.y) <= this.size.width / 2 + 0.035) {
          S.drag = { last: p, off: sub(g.C, p) };
          S.moved = true;
          NZA.audio.click(560);
        }
      } else if (S.step === 2) {
        const si = this.siteAt(l);
        if (si >= 0) { this.padSite(si); return; }
        const i = this.pointAt(l);
        if (i >= 0) this.shapeStart(i);
      } else if (S.step === 3) {
        if (S.cms.state === 'ready' || S.cms.state === 'bad') {
          const c = this.cmsPos(f, g);
          if (c && len(sub(c, p)) <= Math.max(30 * (this.over.height / 1080), 0.05 * g.ppm)) { this.cmsCheck(); return; }
        }
        const si = this.strapAt(l);
        if (si >= 0) this.strapClick(si);
      }
    },
    pointerMove(e) {
      const S = this.S;
      if (!S || !S.drag) return;
      const f = this.frame();
      if (!f) return;
      const p = this.px(e);
      let C;
      if (this.shift || e.shiftKey) {
        const g = this.geom(f, S.pose);
        C = add(g.C, mul(sub(p, S.drag.last), this.tune.fine));
        S.drag.off = sub(C, p);
      } else {
        C = add(p, S.drag.off);
      }
      S.drag.last = p;
      S.pose = this.toPose(f, C, S.pose.phi);
    },
    pointerUp() {
      const S = this.S;
      if (!S) return;
      if (S.drag) S.drag = null;
      if (S.press >= 0) this.shapeEnd();
    },

    /* ─────────────── step 2: pad & shape ─────────────── */
    padY() { return this.size.limbRadius + 0.008; },
    siteAt(l) {
      const S = this.S;
      let best = -1, bd = 0.034;
      S.sites.forEach((s, i) => {
        if (s.padded) return;
        [-1, 1].forEach(sg => { const dd = Math.hypot(l.x - s.x, l.y - sg * this.padY()); if (dd < bd) { bd = dd; best = i; } });
      });
      return best;
    },
    pointAt(l) {
      const S = this.S;
      if (Math.abs(l.y) > this.size.width / 2 + 0.02) return -1;
      let best = -1, bd = 0.032;
      S.points.forEach((pt, i) => { const dd = Math.abs(l.x - pt.x); if (dd < bd) { bd = dd; best = i; } });
      return best;
    },
    nearUnpadded(pt) {
      return this.S.sites.find(s => !s.padded && Math.abs(s.x - pt.x) < 0.045);
    },
    padSite(i) {
      const S = this.S, s = S.sites[i];
      if (s.padded) return;
      s.padded = true; s.pop = 1;
      if (S.tool !== 'pad') S.tool = 'pad';
      NZA.audio.noise(180, { vol: 0.07, lp: 700, hp: 120, attack: 0.1 });
      const J = this.d.joints || {};
      this.pp.flash('ok', T('padded', 'Padded at the %s.', ((s.key === 'prox' ? J.prox : J.dist) || '').toLowerCase()), 1500);
      if (S.sites.every(x => x.padded)) {
        setTimeout(() => { if (this.S === S && S.step === 2) { S.tool = 'shape'; this.enterStep(2, true); } }, 500);
      }
      this.refreshTools();
      this.updateReadout(true);
      this.checkShapeDone();
    },
    shapeStart(i) {
      const S = this.S, pt = S.points[i];
      if (pt.done && pt.f >= this.tune.shapeZone[0]) { this.pp.flash('warn', T('shape_full', 'That point already sits against the limb.'), 1500); return; }
      const site = this.nearUnpadded(pt);
      if (site) {
        const J = this.d.joints || {};
        this.pp.flash('warn', T('pad_first', 'Pad the %s first - shaping over bare bone hurts.', ((site.key === 'prox' ? J.prox : J.dist) || '').toLowerCase()), 2200);
        NZA.audio.click(260);
        if (S.tool !== 'pad') { S.tool = 'pad'; this.enterStep(2, true); }
        return;
      }
      if (S.tool !== 'shape') { S.tool = 'shape'; this.enterStep(2, true); }
      S.press = i;
      pt.f = Math.min(1.04, pt.f + this.tune.shapeClick);
      NZA.audio.noise(120, { vol: 0.05, lp: 900, hp: 200 });
      this.checkTight(pt);
    },
    shapeEnd() {
      const S = this.S, i = S.press;
      S.press = -1;
      if (i < 0) return;
      const pt = S.points[i];
      if (!pt.done && pt.f >= this.tune.shapeZone[0]) { pt.done = true; pt.pop = 1; NZA.audio.click(880); }
      this.updateReadout(true);
      this.checkShapeDone();
    },
    checkTight(pt) {
      if (pt.f > this.tune.shapeZone[1] && !pt.tight) {
        pt.tight = true; pt.f = Math.min(pt.f, 1.04); pt.done = true; this.S.press = -1;
        NZA.audio.click(240);
        this.pp.flash('bad', T('pressure_point', 'Too much: that leaves a pressure point under the splint.'), 2400);
        this.updateReadout(true);
        this.checkShapeDone();
      }
    },
    checkShapeDone() {
      const S = this.S;
      if (!S || S.step !== 2 || !S.points.every(p => p.done) || !S.sites.every(s => s.padded) || S.shapeDone) return;
      S.shapeDone = true;
      const [z0, z1] = this.tune.shapeZone;
      const q = S.points.map(p => (p.tight ? 52 : clamp(100 - Math.abs(p.f - (z0 + z1) / 2) * 140, 60, 100)));
      S.s2 = Math.round(q.reduce((a, b) => a + b, 0) / q.length);
      NZA.audio.success();
      this.pp.flash('ok', T('shape_ok', 'Splint shaped to the limb.'), 2000);
      setTimeout(() => { if (this.S === S) this.enterStep(3); }, 750);
    },

    /* ─────────────── step 3: straps & distal check ─────────────── */
    strapAt(l) {
      const S = this.S;
      if (Math.abs(l.y) > this.size.width / 2 + 0.05) return -1;
      let best = -1, bd = STRAP_W[this.kind] / 2 + 0.02;
      S.straps.forEach((s, i) => { const dd = Math.abs(l.x - s.x); if (dd < bd) { bd = dd; best = i; } });
      return best;
    },
    strapClick(i) {
      const S = this.S, s = S.straps[i];
      if (S.cms.state === 'checking') return;
      if (S.sweeping >= 0 && S.sweeping !== i && S.straps[S.sweeping].state !== 'locked') { this.pp.flash('warn', T('strap_one', 'Finish the strap you are cinching first.'), 1600); return; }
      if (s.state === 'open' || s.state === 'locked') {
        if (s.state === 'locked' && S.cms.state === 'ok') return;
        const relock = s.state === 'locked';
        s.state = relock ? 'sweep' : 'wrap'; s.k = relock ? 1 : s.k; s.ph = 0; S.sweeping = i;
        NZA.audio.noise(relock ? 200 : 340, { vol: 0.08, lp: 5200, hp: 1400, attack: 0.02, release: 0.4 });
        if (S.cms.state === 'bad' || S.cms.state === 'ready') { S.cms.state = 'hidden'; this.cmsEl.hidden = true; if (this.trace) { this.trace.stop(); this.trace = null; } }
        if (relock) this.pp.flash('warn', T('strap_loosened', 'Strap %s loosened - cinch it again.', i + 1), 1800);
        S.tool = 'strap';
        this.enterStep(3, true);
      } else if (s.state === 'sweep') {
        s.state = 'locked'; s.locks += 1; S.sweeping = -1;
        const z = this.tune.strapZone, tn = s.tension;
        s.quality = tn > this.tune.strapTight ? 30 : tn < z[0] ? clamp(78 - (z[0] - tn) * 160, 30, 78) : clamp(100 - Math.abs(tn - (z[0] + z[1]) / 2) * 90, 80, 100);
        s.tight = tn > this.tune.strapTight;
        s.loose = tn < z[0];
        if (s.tight) S.tightEver += 1;
        NZA.audio.click(s.tight ? 300 : s.loose ? 520 : 940);
        this.pp.flash(s.tight ? 'bad' : s.loose ? 'warn' : 'ok', s.tight ? T('strap_tight', 'Strap %s is very tight.', i + 1) : s.loose ? T('strap_loose', 'Strap %s is loose - the splint can slip.', i + 1) : T('strap_ok', 'Strap %s secured.', i + 1), 1800);
        if (S.straps.every(x => x.state === 'locked')) {
          S.cms.state = 'ready'; S.tool = 'cms';
          setTimeout(() => { if (this.S === S) this.enterStep(3, true); }, 400);
        }
      }
      this.refreshTools();
      this.updateReadout(true);
    },
    cmsPos(f, g) {
      const a = this.anc.cms;
      if (a && a.visible !== false) return v(a.x * this.over.width, a.y * this.over.height);
      return add(g.Sd, mul(g.s, 0.06 * g.ppm));
    },
    cmsCheck() {
      const S = this.S, d = this.d;
      if (S.cms.state !== 'ready' && S.cms.state !== 'bad') return;
      S.cms.state = 'checking'; S.cms.checks += 1; S.cms.t = performance.now(); S.cms.shown = -1;
      const tight = S.straps.some(s => s.tight);
      const pulse = d.pulse || 'present';
      const leg = this.kind === 'leg';
      const resp = d.responsive !== false;
      const refill = tight ? 3.6 : Number(d.refill) || (pulse === 'present' ? 1.4 : 3.2);
      const rows = [];
      if (tight) rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_tight', 'Faint pulse · refill %s s', refill.toFixed(1)), tone: 'red' });
      else if (pulse === 'absent') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_absent', 'No pulse below the tourniquet'), tone: 'amber' });
      else if (pulse === 'weak') rows.push({ k: 'C', label: T('circ', 'Circulation'), value: d.pulseWhy || T('c_weak', 'Weak, thready pulse - in shock'), tone: 'amber' });
      else rows.push({ k: 'C', label: T('circ', 'Circulation'), value: T('c_ok', 'Pulse present · refill %s s', refill.toFixed(1)), tone: 'teal' });
      if (!resp) rows.push({ k: 'M', label: T('motor', 'Movement'), value: T('m_unresp', 'Not testable - unresponsive'), tone: 'amber' });
      else rows.push({ k: 'M', label: T('motor', 'Movement'), value: tight ? T('m_tight', 'Barely moves') : (leg ? T('m_leg', 'Wiggles the toes') : T('m_arm', 'Moves the fingers')), tone: tight ? 'amber' : 'teal' });
      if (!resp) rows.push({ k: 'S', label: T('sens', 'Feeling'), value: T('s_unresp', 'Not testable - unresponsive'), tone: 'amber' });
      else rows.push({ k: 'S', label: T('sens', 'Feeling'), value: tight ? T('s_tight', 'Pins and needles') : T('s_ok', 'Feels a light touch'), tone: tight ? 'red' : 'teal' });
      S.cms.rows = rows; S.cms.tight = tight; S.cms.refill = refill;
      S.cms.amp = tight ? 0.22 : pulse === 'absent' ? 0.03 : pulse === 'weak' ? 0.38 : 1;
      this.renderCms(-1);
      this.refreshTools();
      this.updateReadout(true);
      NZA.audio.click(700);
    },
    renderCms(shown) {
      const S = this.S, d = this.d, r = S.cms.rows || [];
      const where = (d.joints && d.joints.cms) || (this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers'));
      const state = S.cms.state;
      const head = state === 'bad' ? T('cms_head_bad', 'Circulation cut off') : state === 'ok' ? T('cms_head_ok', 'All intact below the splint') : T('cms_head', 'Checking the %s', where);
      const C = 2 * Math.PI * 15;
      const refillPct = state === 'checking' ? clamp((performance.now() - S.cms.t) / 1000 / (S.cms.refill || 1.4), 0, 1) : 1;
      if (!this.trace || !this.cmsEl.querySelector('.cv-trace')) {
        this.cmsEl.innerHTML = `
          <div class="hd"><span class="k">${icon('pulse')}${esc(T('cms_kicker', 'Distal check'))}</span><span class="st"></span></div>
          <div class="ttl"></div>
          <div class="wave"><canvas class="cv-trace"></canvas><span class="wl">${esc(T('pleth', 'Pulse below the splint'))}</span><span class="wv"></span></div>
          <div class="rows"></div>`;
        if (this.trace) this.trace.stop();
        this.trace = NZA.vitals.Trace(this.cmsEl.querySelector('.cv-trace'), { type: 'pleth', rate: Number(d.hr) || 88, color: '#3fd0ff', amp: S.cms.amp, speed: 0.32 });
      }
      if (this.trace) this.trace.set({ amp: S.cms.amp, color: S.cms.tight ? '#ff7478' : (S.cms.amp < 0.5 ? '#f3c35a' : '#3fd0ff') });
      this.cmsEl.className = `sp-cms nza-hud solid st-${state}`;
      this.cmsEl.querySelector('.ttl').textContent = head;
      this.cmsEl.querySelector('.st').innerHTML = `<span class="chipx sm ${state === 'ok' ? 'teal' : state === 'bad' ? 'red' : ''}">${esc(state === 'checking' ? T('cms_checking', 'Checking…') : state === 'ok' ? T('cms_ok', 'Intact') : state === 'bad' ? T('cms_bad', 'Cut off') : '')}</span>`;
      this.cmsEl.querySelector('.wv').textContent = S.cms.amp < 0.1 ? '--' : `${Math.round(Number(d.hr) || 88)}`;
      this.cmsEl.querySelector('.rows').innerHTML = r.map((row, i) => `
        <div class="row ${i < shown || state !== 'checking' ? `on ${row.tone}` : ''}">
          <span class="ring">${row.k === 'C' && i <= shown + 1 ? `<svg viewBox="0 0 36 36"><circle class="bg" cx="18" cy="18" r="15"/><circle class="fg" cx="18" cy="18" r="15" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - refillPct)).toFixed(1)}"/></svg>` : ''}<b>${esc(row.k)}</b></span>
          <span class="l">${esc(row.label)}</span>
          <span class="vv">${i < shown || state !== 'checking' ? esc(row.value) : '<i class="dots"><i></i><i></i><i></i></i>'}</span>
        </div>`).join('');
      this.cmsEl.hidden = false;
    },
    cmsTick(now) {
      const S = this.S, d = this.d;
      if (S.cms.state !== 'checking') return;
      if (S.cms.hold) S.cms.t = now - 1700;      // preview: freeze the check half-way
      const el = (now - S.cms.t) / 1000;
      const step = Math.max(0.75, (S.cms.refill || 1.4) * 0.6);
      const shown = Math.min(3, Math.floor(el / step));
      if (shown !== S.cms.shown || (shown === 0 && el < S.cms.refill)) {
        const changed = shown !== S.cms.shown;
        S.cms.shown = shown; this.renderCms(shown);
        if (changed && shown > 0) NZA.audio.tick();
        if (changed && (shown === 1 || shown === 2) && d.responsive !== false && (!NZA.inGame || d.speech !== false)) {
          const leg = this.kind === 'leg', tight = S.cms.tight;
          const line = shown === 1 ? (tight ? T('say_m_tight', 'I... can barely move them.') : (leg ? T('say_m_leg', 'Yeah, I can move my toes.') : T('say_m_arm', 'Yeah, my fingers move.')))
            : (tight ? T('say_s_tight', 'It\'s all pins and needles down there.') : T('say_s_ok', 'I can feel that, yes.'));
          NZA.speech({ name: d.name || T('patient', 'Patient'), text: line, ms: 2200, role: T('patient', 'Patient') });
        }
      }
      if (el >= 3 * step + 0.4) {
        if (S.cms.tight) {
          S.cms.state = 'bad'; S.cms.fixed = true;
          NZA.audio.fail();
          this.pp.flash('bad', T('cms_fail', 'No good pulse below the splint. Click the tight strap to loosen it, cinch it again and re-check.'), 5200);
          this.renderCms(3);
          this.enterStep(3, true);
        } else {
          S.cms.state = 'ok';
          this.renderCms(3);
          this.refreshTools();
          this.finish();
        }
      }
    },

    finish() {
      const S = this.S;
      if (S.finished) return;
      S.finished = true;
      const q = S.straps.map(s => s.quality);
      const strapAvg = q.reduce((a, b) => a + b, 0) / q.length;
      const checksPenalty = Math.max(0, S.cms.checks - (S.cms.fixed ? 2 : 1)) * 4;
      S.s3 = Math.round(clamp(strapAvg + (S.cms.fixed ? 4 : 0) - checksPenalty, 25, 100));
      const score = Math.round(clamp(S.s1 * 0.4 + S.s2 * 0.3 + S.s3 * 0.3, 0, 100));
      const result = {
        score, align: S.s1, mould: S.s2, straps: S.s3, cms: 'ok', checks: S.cms.checks,
        pressure: S.points.filter(p => p.tight).length, padded: S.sites.filter(s => s.padded).length,
        tight: S.tightEver, loose: S.straps.filter(s => s.loose).length, resets: S.resets,
        time: Math.round((performance.now() - S.t0) / 100) / 10,
      };
      S.result = result;
      NZA.audio.success();
      this.pp.set({ title: T('securing', 'Recording the splint…'), titleTone: '', text: T('securing_text', 'Distal check intact. Writing it on the patient record.'), tools: this.toolsFor(), wide: { label: T('score', 'Score'), value: score, unit: '', tone: 'teal', meter: { value: score / 100 } } });
      NZA.post(`${APP}:finish`, result).then(r => {
        if (!NZA.inGame && r && r.outcome) this.showResult(r.outcome);
      });
    },

    showResult(o) {
      const S = this.S;
      if (!S || !this.pp) return;
      const r = S.result || {};
      const score = clamp(Math.round(o.score ?? r.score ?? 0), 0, 100);
      const grade = o.grade || (score >= 90 ? 'S' : score >= 80 ? 'A' : score >= 68 ? 'B' : score >= 55 ? 'C' : score >= 40 ? 'D' : 'F');
      const ring = 2 * Math.PI * 34;
      const row = (lab, val, ic) => `<div class="r"><span class="ri">${icon(ic)}</span><span class="rl">${esc(lab)}</span><span class="rb"><i style="width:${clamp(val, 0, 100)}%"></i></span><b>${Math.round(val)}</b></div>`;
      const t = Math.round(r.time || 0);
      this.resEl.innerHTML = `
        <div class="hd"><span class="k">${icon('splint')}${esc(T('res_kicker', 'Splint record'))}</span><span class="tm">${icon('timer')}${NZA.fmt.time(t)}</span></div>
        <div class="top">
          <div class="dial g-${esc(grade)}"><svg viewBox="0 0 80 80"><circle class="bg" cx="40" cy="40" r="34"/><circle class="fg" cx="40" cy="40" r="34" stroke-dasharray="${ring.toFixed(1)}" stroke-dashoffset="${(ring * (1 - score / 100)).toFixed(1)}"/></svg><b>${esc(grade)}</b><small>${score}</small></div>
          <div class="who"><div class="ttl">${esc(this.d.regionLabel || '')}</div><div class="dv">${esc(this.d.deviceLabel || '')} · ${esc(this.d.deviceModel || '')}</div>
            <div class="chips"><span class="chipx sm teal">${icon('check')}${esc(T('res_cms', 'Distal check intact'))}</span>${r.pressure ? `<span class="chipx sm amber">${esc(T('res_press', '%s pressure point(s)', r.pressure))}</span>` : ''}${S.cms.fixed ? `<span class="chipx sm">${esc(T('res_fixed', 'Strap re-done'))}</span>` : ''}</div></div>
        </div>
        <div class="map">${this.splintMapSVG()}</div>
        <div class="bars">${row(T('res_align', 'Alignment'), r.align ?? score, 'ruler')}${row(T('res_mould', 'Shaping'), r.mould ?? score, 'hand')}${row(T('res_straps', 'Straps'), r.straps ?? score, 'cuff')}</div>
        ${o.msg ? `<div class="msg">${icon('check')}<span>${esc(o.msg)}</span></div>` : ''}`;
      this.resEl.hidden = false;
      this.cmsEl.hidden = true;
      if (this.trace) { this.trace.stop(); this.trace = null; }
      this.pp.complete({
        title: T('done_title', 'Splint secured'),
        text: T('done_text', 'The limb is held above and below the break. Re-check the pulse below it on the way in.'),
        label: T('done', 'Done'), onDone: () => this.done(),
      });
      const cmsOk = (S.cms.rows || []).every(x => x.tone === 'teal');
      this.pp.set({
        wide: { label: T('score', 'Score'), value: score, tone: 'teal', meter: { value: score / 100 }, caption: T('grade', 'Grade %s', grade), captionTone: 'teal' },
        stats: [
          { id: 'tm', label: T('res_time', 'Time'), value: NZA.fmt.time(t) },
          { id: 'pp', label: T('pressure_pts', 'Pressure points'), value: r.pressure || 0, tone: r.pressure ? 'amber' : 'teal' },
          { id: 'cm', label: T('cms', 'Distal check'), value: cmsOk ? T('cms_ok', 'Intact') : T('cms_noted', 'Noted'), small: true, tone: cmsOk ? 'teal' : 'amber' },
        ],
        hints: [{ keys: ['Enter'], label: T('h_finish', 'Finish') }],
        abort: false,
      });
    },

    // top view of the finished splint for the record: joint lines, break, pads, shaping points
    // (tone = how well each one sits), straps with their tension, distal check
    splintMapSVG() {
      const S = this.S, d = this.d, J = d.joints || {};
      const W = 300, H = 96, x0 = 14, x1 = 286, cy = 42, L = this.Ls;
      const X = x => x0 + (x + L / 2) / L * (x1 - x0);
      const hw = 15, lr = 9;
      const [z0, z1] = this.tune.shapeZone;
      const zone = this.tune.strapZone;
      const plate = this.kind === 'leg' && this.segment === 'lower';
      let g = `<defs><linearGradient id="spm-f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#26303a"/><stop offset=".5" stop-color="#1a2128"/><stop offset="1" stop-color="#26303a"/></linearGradient>
        <linearGradient id="spm-l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="rgba(120,150,190,.28)"/><stop offset=".5" stop-color="rgba(150,180,215,.42)"/><stop offset="1" stop-color="rgba(120,150,190,.28)"/></linearGradient></defs>`;
      g += `<rect x="${x0}" y="${cy - hw}" width="${x1 - x0}" height="${hw * 2}" rx="9" fill="url(#spm-f)" stroke="#2fe0d0" stroke-width="1.6"/>`;
      if (plate) g += `<rect x="${x1 - 3}" y="${cy - hw - 4}" width="6" height="${hw * 2 + 8}" rx="2.5" fill="#0b8379" stroke="#2fe0d0" stroke-width="1"/>`;
      g += `<rect x="${x0 - 6}" y="${cy - lr}" width="${x1 - x0 + 4}" height="${lr * 2}" rx="${lr}" fill="url(#spm-l)"/>`;
      // ruler ticks along the top edge
      for (let cm = 0; cm <= Math.floor(L * 100); cm += 5) { const x = X(-L / 2 + cm / 100); g += `<line x1="${x.toFixed(1)}" y1="${cy - hw - 2}" x2="${x.toFixed(1)}" y2="${cy - hw - (cm % 10 ? 5 : 8)}" stroke="rgba(214,224,228,.35)" stroke-width="1"/>`; }
      // joints
      S.sites.forEach((s, i) => {
        const x = X(s.x);
        g += `<line x1="${x.toFixed(1)}" y1="${cy - hw}" x2="${x.toFixed(1)}" y2="${cy + hw}" stroke="#2fe0d0" stroke-width="1.2" stroke-dasharray="2.5 2"/>`;
        if (s.padded) [-1, 1].forEach(sg => { g += `<ellipse cx="${x.toFixed(1)}" cy="${cy + sg * (lr + 3)}" rx="6" ry="2.6" fill="#e6ecee" opacity=".9"/>`; });
        g += `<text x="${x.toFixed(1)}" y="${H - 6}" class="mj" text-anchor="middle">${esc(((i === 0 ? J.prox : J.dist) || '').toUpperCase())}</text>`;
        g += `<line x1="${x.toFixed(1)}" y1="${cy + hw + 3}" x2="${x.toFixed(1)}" y2="${H - 17}" stroke="rgba(47,224,208,.35)" stroke-width="1"/>`;
      });
      // the break
      const fx = X(S.xFr);
      let zz = `M${fx - 2} ${cy - lr + 1}`;
      for (let i = 1; i <= 5; i++) zz += ` L${fx + (i % 2 ? 3 : -3)} ${cy - lr + 1 + (lr * 2 - 2) * i / 5}`;
      g += `<path d="${zz}" fill="none" stroke="#ff6b70" stroke-width="1.6" stroke-linejoin="round"/>`;
      // shaping points
      S.points.forEach(p => {
        const x = X(p.x), ok = p.f >= z0 && p.f <= z1 && !p.tight;
        g += `<circle cx="${x.toFixed(1)}" cy="${cy}" r="2.6" fill="${p.tight ? '#f3c35a' : ok ? '#2fe0d0' : 'rgba(255,255,255,.6)'}" stroke="#0c0d10" stroke-width="1"/>`;
      });
      // straps + tension
      S.straps.forEach(st => {
        const x = X(st.x), w = Math.max(8, STRAP_W[this.kind] / L * (x1 - x0));
        const tone = st.tight ? '#ff7478' : st.tension < zone[0] ? '#f3c35a' : '#2fe0d0';
        g += `<rect x="${(x - w / 2).toFixed(1)}" y="${cy - hw - 2}" width="${w.toFixed(1)}" height="${hw * 2 + 4}" rx="2" fill="rgba(28,31,34,.92)" stroke="${tone}" stroke-width="1"/>`;
        g += `<text x="${x.toFixed(1)}" y="${cy - hw - 9}" class="mt" text-anchor="middle" fill="${tone}">${Math.round(st.tension * 100)}</text>`;
      });
      // distal check
      const cx = X(L / 2) + (plate ? -2 : 0), cyc = cy + hw + 10;
      g += `<path d="M${cx} ${cyc - 6} L${cx + 6} ${cyc} L${cx} ${cyc + 6} L${cx - 6} ${cyc} Z" fill="rgba(8,175,162,.3)" stroke="#2fe0d0" stroke-width="1.2"/><path d="M${cx - 2.6} ${cyc} l1.8 1.9 3.4 -3.6" fill="none" stroke="#2fe0d0" stroke-width="1.4" stroke-linecap="round"/>`;
      return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${g}</svg>`;
    },

    done() {
      NZA.post(`${APP}:done`, {});
      if (!NZA.inGame) NZA.close(APP);
    },

    /* ─────────────── frame loop ─────────────── */
    loop(now) {
      this.raf = 0;
      const S = this.S;
      if (!S || !S.active) return;
      const dt = Math.min(0.05, (now - (this.last || now)) / 1000);
      this.last = now;
      if (this.previewTick) this.previewTick(now, dt);
      this.update(now, dt);
      this.draw(now);
      this.raf = requestAnimationFrame(this.loop);
    },

    update(now, dt) {
      const S = this.S, t = this.tune;
      const f = this.frame();
      this.hintEl.hidden = !!f;
      if (!f) { this.hintEl.textContent = T('no_view', 'Turn the view until you can see the limb.'); return; }
      if (!S.pose0) { S.side = this.bodySide(f); S.pose = this.initialPose(f); S.pose0 = Object.assign({}, S.pose); S.intro = now; }
      const fine = this.shift ? t.fine : 1;

      if (S.step === 1 && !S.locked) {
        const h = this.held;
        let phi = S.pose.phi;
        const rs = t.rotateSpeed * Math.PI / 180 * fine * dt;
        if (h.has('rotL')) phi -= rs;
        if (h.has('rotR')) phi += rs;
        let C = this.geom(f, S.pose).C;
        const ns = t.nudgeSpeed * f.ppm * fine * dt;
        if (h.has('up')) C = add(C, v(0, -ns));
        if (h.has('down')) C = add(C, v(0, ns));
        if (h.has('left')) C = add(C, v(-ns, 0));
        if (h.has('right')) C = add(C, v(ns, 0));
        if (h.size) { S.pose = this.toPose(f, C, phi); S.moved = true; }
        S.pose.phi = Math.atan2(Math.sin(S.pose.phi), Math.cos(S.pose.phi));
        const g = this.geom(f, S.pose);
        S.err.p = len(sub(g.Sp, f.Tp)) / f.ppm;
        S.err.d = len(sub(g.Sd, f.Td)) / f.ppm;
        S.err.a = Math.abs(S.pose.phi) * 180 / Math.PI;
        const angOk = S.err.a <= t.angleTolerance;
        const ap = S.err.p < t.tolerance && angOk, ad = S.err.d < t.tolerance && angOk;
        if (ap && !S.aligned.p) { S.snap.p = now; NZA.audio.tone(1180, 60, { vol: 0.06, type: 'triangle' }); }
        if (ad && !S.aligned.d) { S.snap.d = now; NZA.audio.tone(1320, 60, { vol: 0.06, type: 'triangle' }); }
        S.aligned.p = ap; S.aligned.d = ad;
        const steady = !S.drag && this.held.size === 0;
        if (ap && ad && steady && S.moved) S.alignHold += dt; else S.alignHold = 0;
        if (S.alignHold >= t.lockHold) this.lockSplint();
        this.updateReadout();
      } else if (S.step === 1 && S.lockAnim) {
        const k = easeOut((now - S.lockAnim.t0) / 320);
        const a = S.lockAnim.from;
        S.pose = { cu: lerp(a.cu, 0, k), cv: lerp(a.cv, 0, k), phi: lerp(a.phi, 0, k) };
      }

      if (S.step === 2 && S.press >= 0 && !this._holdPreview) {
        const pt = S.points[S.press];
        pt.f += dt / t.shapeSeconds * (this.shift ? 0.45 : 1);
        this.checkTight(pt);
        this.updateReadout();
      }
      S.points.forEach(p => { if (p.pop > 0) p.pop = Math.max(0, p.pop - dt * 2.5); });
      S.sites.forEach(p => { if (p.pop > 0) p.pop = Math.max(0, p.pop - dt * 2.2); });

      if (S.step === 3) {
        S.straps.forEach(s => {
          if (s.state === 'wrap') { s.k += dt / 0.5; if (s.k >= 1) { s.k = 1; s.state = 'sweep'; s.ph = 0; NZA.audio.noise(90, { vol: 0.05, lp: 3000, hp: 800 }); } }
          if (s.state === 'sweep') {
            s.ph += dt / t.strapPeriod;
            s.tension = 0.5 - 0.5 * Math.cos(s.ph * Math.PI * 2);
            this.updateReadout();
          }
        });
        this.cmsTick(now);
      }
    },

    /* ─────────────── drawing ─────────────── */
    draw(now) {
      const fu = NZA.fitCanvas(this.under), fo = NZA.fitCanvas(this.over);
      const w = fo.w, h = fo.h;
      const uc = this.uc, c = this.oc;
      c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, w, h);
      const clearUnder = () => { uc.setTransform(1, 0, 0, 1, 0, 0); uc.clearRect(0, 0, fu.w, fu.h); };
      const S = this.S;
      const f = this.frame();
      const U = h / 1080;
      this.U = U;
      const tags = {};
      if (!f) { this.syncTags(tags); if (this.gl) { this.gl.update({ visible: false }); this.gl.clear(); } if (this._shKey) { clearUnder(); this._shKey = ''; } return; }
      const g = this.geom(f, S.pose);
      const introK = easeOut((now - (S.intro || now)) / 420);

      // 3D splint
      if (this.gl) {
        if (!this.glBuilt) {
          this.gl.build({
            kind: this.kind, segment: this.segment, L: this.Ls, width: this.size.width, depth: this.size.depth, th: this.size.wall,
            limbR: this.size.limbRadius, plate: this.kind === 'leg' && this.segment === 'lower', strapW: STRAP_W[this.kind],
            sites: S.sites.map(s => ({ x: s.x })), strapX: S.straps.map(s => s.x), anchorSide: -S.side,
            print: {
              prox: (this.d.joints && this.d.joints.prox) || T('j_prox', 'Upper joint'),
              dist: (this.d.joints && this.d.joints.dist) || T('j_dist', 'Lower joint'),
              model: this.d.deviceModel || '',
              name: this.kind === 'leg' ? T('print_leg', 'Posterior leg splint') : T('print_arm', 'Posterior arm splint'),
              use: T('print_use', 'Single patient use · latex free'),
              warn: T('print_warn', 'Check pulse below'),
              warn2: T('print_warn2', 'after every strap'),
            },
          });
          this.glBuilt = true;
        }
        this.gl.update({
          visible: true, C: g.C, s: g.s, ppm: f.ppm, H: h,
          limbA: f.limbA, limbB: f.limbB, limbR: this.size.limbRadius * f.ppm, fade: 1, opacity: introK,
          points: S.step >= 2 ? S.points : [], zone: this.tune.shapeZone,
          pads: S.sites.map(s => ({ on: s.padded, pop: s.pop })),
          straps: S.straps.map(s => ({ k: S.step === 3 ? s.k : 0, tension: s.state === 'locked' || s.state === 'sweep' ? s.tension : 0, show: S.step >= 1 })),
        });
        this.gl.render(w, h, this.fov);
      }
      const shKey = `${Math.round(g.C.x)},${Math.round(g.C.y)},${g.s.x.toFixed(3)},${g.s.y.toFixed(3)},${g.ppm.toFixed(1)},${introK.toFixed(2)},${fu.w}x${fu.h},${S.step === 3 ? S.straps.map(x => x.k.toFixed(2)).join('/') : ''}`;
      if (shKey !== this._shKey) { this._shKey = shKey; clearUnder(); this.drawShadow(f, g, introK); }
      if (!this.gl) this.drawFlatSplint(f, g);

      // fracture site on the limb
      this.drawBreak(f, now, S.step);

      if (S.step === 1 && !S.locked) this.drawStep1(f, g, now, tags);
      if (S.step === 1 && (now - (S.intro || 0)) < 1700) this.drawGhost(f, now);
      if (S.step === 2) this.drawStep2(f, g, now, tags);
      if (S.step === 3) this.drawStep3(f, g, now, tags);
      this.syncTags(tags);
    },

    // soft contact shadow + the foot plate's cast shadow (light from the upper left)
    drawShadow(f, g, k) {
      const c = this.uc, U = this.U, o = this.size;
      const half = o.width / 2 + o.wall + 0.004;
      const pts = [];
      const N = 24;
      for (let i = 0; i <= N; i++) pts.push(this.world(g, -g.H + 2 * g.H * i / N, -half));
      for (let i = N; i >= 0; i--) pts.push(this.world(g, -g.H + 2 * g.H * i / N, half));
      c.save();
      c.globalAlpha = 0.55 * k;
      c.filter = `blur(${Math.round(9 * U)}px)`;
      c.fillStyle = 'rgba(0,0,0,.85)';
      c.translate(4 * U, 7 * U);
      c.beginPath(); pts.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y))); c.closePath(); c.fill();
      if (this.kind === 'leg' && this.segment === 'lower') {
        const a = this.world(g, g.H, -half), b = this.world(g, g.H, half);
        const lift = v(0.07 * g.ppm, 0.11 * g.ppm);
        c.globalAlpha = 0.35 * k;
        c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.lineTo(b.x + lift.x, b.y + lift.y); c.lineTo(a.x + lift.x, a.y + lift.y); c.closePath(); c.fill();
      }
      c.restore();
      // the limb lies on the splint: no splint shadow on it
      c.save();
      c.globalCompositeOperation = 'destination-out';
      c.filter = `blur(${Math.round(5 * U)}px)`;
      c.strokeStyle = '#000'; c.lineCap = 'round'; c.lineWidth = 2 * o.limbRadius * g.ppm * 0.94;
      c.beginPath(); c.moveTo(f.limbA.x, f.limbA.y); c.lineTo(f.limbB.x, f.limbB.y); c.stroke();
      c.restore();
      // straps over the limb throw a soft shadow on it
      if (this.S.step === 3) {
        const sw = STRAP_W[this.kind], lr = o.limbRadius * 1.08;
        c.save();
        c.filter = `blur(${Math.round(4 * U)}px)`;
        c.fillStyle = 'rgba(0,0,0,.9)';
        c.translate(5 * U, 8 * U);
        this.S.straps.forEach(st => {
          if (st.k < 0.05) return;
          c.globalAlpha = 0.42 * k * easeOut(st.k);
          const p1 = this.world(g, st.x - sw / 2, -lr), p2 = this.world(g, st.x + sw / 2, -lr), p3 = this.world(g, st.x + sw / 2, lr), p4 = this.world(g, st.x - sw / 2, lr);
          c.beginPath(); c.moveTo(p1.x, p1.y); c.lineTo(p2.x, p2.y); c.lineTo(p3.x, p3.y); c.lineTo(p4.x, p4.y); c.closePath(); c.fill();
        });
        c.restore();
      }
    },

    // 2D fallback when WebGL is unavailable
    drawFlatSplint(f, g) {
      const c = this.oc, U = this.U, o = this.size;
      const half = o.width / 2;
      const pts = [];
      for (let i = 0; i <= 20; i++) pts.push(this.world(g, -g.H + 2 * g.H * i / 20, -half));
      for (let i = 20; i >= 0; i--) pts.push(this.world(g, -g.H + 2 * g.H * i / 20, half));
      c.save();
      c.beginPath(); pts.forEach((p, i) => (i ? c.lineTo(p.x, p.y) : c.moveTo(p.x, p.y))); c.closePath();
      c.fillStyle = 'rgba(12,154,142,.55)'; c.fill();
      c.lineWidth = 2 * U; c.strokeStyle = COL.tealHi; c.stroke();
      c.restore();
    },

    diamond(c, x, y, r) { c.beginPath(); c.moveTo(x, y - r); c.lineTo(x + r, y); c.lineTo(x, y + r); c.lineTo(x - r, y); c.closePath(); },

    drawBreak(f, now, step) {
      const c = this.oc, U = this.U, S = this.S;
      const p = add(f.P, mul(f.u, f.L * S.frac));
      const r = this.size.limbRadius * f.ppm * 0.75;
      const a = Math.atan2(f.u.y, f.u.x) + Math.PI / 2;
      c.save();
      c.translate(p.x, p.y); c.rotate(a);
      c.globalAlpha = step === 1 ? 0.95 : 0.55;
      c.shadowColor = 'rgba(229,72,77,.8)'; c.shadowBlur = 10 * U;
      c.strokeStyle = COL.redHi; c.lineWidth = 2.2 * U; c.lineJoin = 'round';
      c.beginPath();
      const n = 6;
      for (let i = 0; i <= n; i++) { const x = -r + (2 * r * i) / n, y = (i % 2 ? 1 : -1) * 4 * U; i ? c.lineTo(x, y) : c.moveTo(x, y); }
      c.stroke();
      c.restore();
    },

    drawGhost(f, now) {
      const c = this.oc, U = this.U, S = this.S;
      const k = 1 - clamp((now - (S.intro || now) - 300) / 1400, 0, 1);
      if (k <= 0) return;
      const g0 = this.geom(f, { cu: 0, cv: 0, phi: 0 });
      const half = this.size.width / 2 + this.size.wall;
      c.save();
      c.globalAlpha = 0.7 * k;
      c.setLineDash([6 * U, 5 * U]); c.lineDashOffset = -now / 40;
      c.strokeStyle = COL.tealHi; c.lineWidth = 1.6 * U;
      const a = this.world(g0, -g0.H, -half), b = this.world(g0, g0.H, -half), cc = this.world(g0, g0.H, half), d = this.world(g0, -g0.H, half);
      c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.lineTo(cc.x, cc.y); c.lineTo(d.x, d.y); c.closePath(); c.stroke();
      c.restore();
    },

    drawTarget(pt, r, ok, now, snapAt) {
      const c = this.oc, U = this.U;
      c.save();
      const spin = now / 900;
      // corner ticks (reticle)
      c.strokeStyle = ok ? COL.tealHi : 'rgba(255,255,255,.7)';
      c.lineWidth = 1.6 * U;
      for (let i = 0; i < 4; i++) {
        const a = spin * (ok ? 0 : 1) + i * Math.PI / 2;
        const r1 = r + 6 * U, r2 = r + 12 * U;
        c.beginPath(); c.moveTo(pt.x + Math.cos(a) * r1, pt.y + Math.sin(a) * r1); c.lineTo(pt.x + Math.cos(a) * r2, pt.y + Math.sin(a) * r2); c.stroke();
      }
      // diamond
      this.diamond(c, pt.x, pt.y, r);
      c.fillStyle = ok ? 'rgba(8,175,162,.24)' : 'rgba(12,13,16,.28)';
      c.fill();
      c.setLineDash(ok ? [] : [4 * U, 3 * U]);
      c.lineDashOffset = -now / 50;
      c.lineWidth = (ok ? 2.4 : 1.8) * U;
      c.strokeStyle = ok ? COL.tealHi : 'rgba(255,255,255,.9)';
      c.shadowColor = ok ? 'rgba(47,224,208,.8)' : 'rgba(0,0,0,.7)'; c.shadowBlur = (ok ? 12 : 6) * U;
      c.stroke();
      c.setLineDash([]); c.shadowBlur = 0;
      this.diamond(c, pt.x, pt.y, 3.2 * U);
      c.fillStyle = ok ? COL.tealHi : '#fff'; c.fill();
      // snap burst
      const sk = snapAt ? (now - snapAt) / 450 : 1;
      if (ok && sk < 1) {
        c.globalAlpha = 1 - sk;
        c.strokeStyle = COL.tealHi; c.lineWidth = 2 * U;
        this.diamond(c, pt.x, pt.y, r + sk * 22 * U); c.stroke();
      }
      c.restore();
    },

    drawStep1(f, g, now, tags) {
      const c = this.oc, U = this.U, S = this.S, t = this.tune;
      const tol = t.tolerance * f.ppm;
      const J = this.d.joints || {};
      // limb axis + reach past the joints
      c.save();
      c.setLineDash([2 * U, 6 * U]); c.lineCap = 'round';
      c.lineWidth = 1.6 * U; c.strokeStyle = 'rgba(255,255,255,.4)';
      c.beginPath(); c.moveTo(f.P.x, f.P.y); c.lineTo(f.D.x, f.D.y); c.stroke();
      c.strokeStyle = 'rgba(47,224,208,.75)';
      c.beginPath(); c.moveTo(f.Tp.x, f.Tp.y); c.lineTo(f.P.x, f.P.y); c.moveTo(f.D.x, f.D.y); c.lineTo(f.Td.x, f.Td.y); c.stroke();
      c.setLineDash([]);
      [f.P, f.D].forEach(p => { c.fillStyle = 'rgba(255,255,255,.85)'; c.beginPath(); c.arc(p.x, p.y, 2.4 * U, 0, Math.PI * 2); c.fill(); });
      c.restore();
      this.drawTarget(f.Tp, Math.max(9 * U, tol), S.aligned.p, now, S.snap.p);
      this.drawTarget(f.Td, Math.max(9 * U, tol), S.aligned.d, now, S.snap.d);
      // splint ends + connectors
      [[g.Sp, f.Tp, S.aligned.p, 'cp'], [g.Sd, f.Td, S.aligned.d, 'cd']].forEach(([a, b, ok, id]) => {
        c.save();
        const half = this.size.width * 0.32 * g.ppm;
        c.strokeStyle = ok ? COL.tealHi : '#fff'; c.lineWidth = 2.6 * U; c.lineCap = 'round';
        c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 5 * U;
        c.beginPath(); c.moveTo(a.x - g.m.x * half, a.y - g.m.y * half); c.lineTo(a.x + g.m.x * half, a.y + g.m.y * half); c.stroke();
        c.shadowBlur = 0;
        const dd = len(sub(a, b));
        if (!ok && dd > 6 * U) {
          c.strokeStyle = 'rgba(255,255,255,.7)'; c.lineWidth = 1.3 * U; c.setLineDash([3 * U, 4 * U]); c.lineDashOffset = -now / 60;
          c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.stroke();
        }
        c.restore();
      });
      // grip
      const hd = g.C, r = 15 * U;
      c.save();
      c.translate(hd.x, hd.y); c.rotate(Math.atan2(g.s.y, g.s.x));
      c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 10 * U;
      this.diamond(c, 0, 0, r);
      c.fillStyle = S.drag ? 'rgba(8,175,162,.85)' : 'rgba(12,13,16,.82)'; c.fill();
      c.shadowBlur = 0;
      c.lineWidth = 2 * U; c.strokeStyle = COL.tealHi; c.stroke();
      c.strokeStyle = S.drag ? '#00201d' : COL.tealHi; c.lineWidth = 1.6 * U; c.lineCap = 'round';
      [[0, -1], [1, 0], [0, 1], [-1, 0]].forEach(([x, y]) => {
        const b = 6.5 * U, tip = b + 3 * U, w = 2.8 * U;
        c.beginPath(); c.moveTo(x * b + y * w, y * b - x * w); c.lineTo(x * tip, y * tip); c.lineTo(x * b - y * w, y * b + x * w); c.stroke();
      });
      c.restore();
      if (S.alignHold > 0) {
        c.save(); c.strokeStyle = COL.tealHi; c.lineWidth = 3 * U; c.lineCap = 'round';
        c.shadowColor = 'rgba(47,224,208,.8)'; c.shadowBlur = 10 * U;
        c.beginPath(); c.arc(hd.x, hd.y, r + 9 * U, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * clamp(S.alignHold / t.lockHold, 0, 1)); c.stroke(); c.restore();
      }
      // angle arc
      if (S.err.a > 1.5) {
        const base = Math.atan2(f.u.y, f.u.x), cur = Math.atan2(g.s.y, g.s.x);
        const R2 = 44 * U;
        c.save();
        c.strokeStyle = S.err.a > t.angleTolerance ? COL.amberHi : 'rgba(255,255,255,.75)'; c.lineWidth = 1.6 * U;
        c.beginPath(); c.arc(hd.x, hd.y, R2, Math.min(base, cur), Math.max(base, cur)); c.stroke();
        c.setLineDash([3 * U, 3 * U]); c.strokeStyle = 'rgba(255,255,255,.35)';
        c.beginPath(); c.moveTo(hd.x, hd.y); c.lineTo(hd.x + Math.cos(base) * (R2 + 10 * U), hd.y + Math.sin(base) * (R2 + 10 * U)); c.stroke();
        c.restore();
        tags.ang = { at: add(hd, mul(rotv(f.u, (cur - base) / 2), R2 + 16 * U)), label: `${Math.round(S.err.a)}°`, tone: S.err.a > t.angleTolerance ? 'amber mono' : 'mono', off: 0, center: true };
      }
      const away = mul(f.n, S.side);
      tags.prox = { at: f.Tp, label: J.prox || T('j_prox', 'Upper joint'), sub: S.aligned.p ? T('tag_seated', 'Seated') : T('tag_off', '%s mm off', mm(S.err.p)), tone: S.aligned.p ? 'ok' : '', off: tol + 18 * U, dir: away };
      tags.dist = { at: f.Td, label: J.dist || T('j_dist', 'Lower joint'), sub: S.aligned.d ? T('tag_seated', 'Seated') : T('tag_off', '%s mm off', mm(S.err.d)), tone: S.aligned.d ? 'ok' : '', off: tol + 18 * U, dir: away };
      tags.grip = { at: hd, label: S.aligned.p && S.aligned.d ? T('tag_hold', 'Hold still') : T('tag_drag', 'Grab & slide'), tone: 'teal', off: r + 14 * U, dir: mul(away, -1) };
    },

    drawStep2(f, g, now, tags) {
      const c = this.oc, U = this.U, S = this.S, t = this.tune;
      const z = t.shapeZone;
      const J = this.d.joints || {};
      // air gap bands along both walls where the splint isn't shaped yet
      const limbR = this.size.limbRadius;
      const gapW = Math.max(0.008, this.size.width / 2 - this.size.wall - limbR - 0.003);
      c.save();
      const N = 40;
      [-1, 1].forEach(sg => {
        for (let i = 0; i < N; i++) {
          const x0 = -g.H + 2 * g.H * i / N, x1 = -g.H + 2 * g.H * (i + 1) / N, xm = (x0 + x1) / 2;
          let shaped = 0;
          S.points.forEach(p => { const gg = Math.exp(-((xm - p.x) ** 2) / (2 * 0.04 * 0.04)); shaped = Math.max(shaped, Math.min(1, p.f / z[0]) * gg); });
          const gap = 1 - shaped;
          if (gap < 0.08) continue;
          const a = this.world(g, x0, sg * (limbR + 0.002)), b = this.world(g, x1, sg * (limbR + 0.002));
          const cc = this.world(g, x1, sg * (limbR + 0.004 + gapW * gap * 1.6)), d = this.world(g, x0, sg * (limbR + 0.004 + gapW * gap * 1.6));
          c.fillStyle = `rgba(243,195,90,${0.1 + 0.16 * gap})`;
          c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.lineTo(cc.x, cc.y); c.lineTo(d.x, d.y); c.closePath(); c.fill();
        }
      });
      c.restore();
      // pad sites
      const padMode = S.tool === 'pad';
      S.sites.forEach((s, i) => {
        [-1, 1].forEach(sg => {
          const p = this.world(g, s.x, sg * this.padY());
          const r = (s.padded ? 7 : 10 + Math.sin(now / 240 + i) * 1.5) * U * (1 + s.pop * 0.4);
          c.save();
          this.diamond(c, p.x, p.y, r);
          c.fillStyle = s.padded ? 'rgba(8,175,162,.55)' : padMode ? 'rgba(229,165,10,.3)' : 'rgba(12,13,16,.55)';
          c.fill();
          c.lineWidth = 1.8 * U; c.setLineDash(s.padded ? [] : [3 * U, 2.5 * U]); c.lineDashOffset = -now / 60;
          c.strokeStyle = s.padded ? COL.tealHi : padMode ? COL.amberHi : 'rgba(255,255,255,.6)';
          c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 5 * U;
          c.stroke();
          c.restore();
        });
        if (!s.padded && padMode) {
          const p = this.world(g, s.x, S.side * (this.padY() + 0.012));
          tags[`site${i}`] = { at: p, label: T('tag_pad', 'Pad the %s', ((s.key === 'prox' ? J.prox : J.dist) || '').toLowerCase()), tone: 'amber', off: 16 * U, dir: mul(g.m, S.side) };
        }
      });
      // shaping points (on the limb axis)
      let next = -1;
      S.points.forEach((pt, i) => { if (next < 0 && !pt.done) next = i; });
      const shapeMode = S.tool === 'shape';
      S.points.forEach((pt, i) => {
        const p = this.world(g, pt.x, 0);
        const r = 11 * U * (1 + pt.pop * 0.35);
        const blocked = !!this.nearUnpadded(pt);
        c.save();
        c.globalAlpha = shapeMode || pt.done ? 1 : 0.55;
        c.shadowColor = 'rgba(0,0,0,.65)'; c.shadowBlur = 7 * U;
        c.fillStyle = pt.tight ? 'rgba(229,165,10,.45)' : pt.done ? 'rgba(8,175,162,.5)' : 'rgba(12,13,16,.78)';
        c.beginPath(); c.arc(p.x, p.y, r, 0, Math.PI * 2); c.fill();
        c.shadowBlur = 0;
        const a0 = -Math.PI / 2;
        c.lineWidth = 3.2 * U;
        c.strokeStyle = 'rgba(255,255,255,.14)';
        c.beginPath(); c.arc(p.x, p.y, r, 0, Math.PI * 2); c.stroke();
        c.strokeStyle = 'rgba(47,224,208,.5)'; c.lineWidth = 2.4 * U;
        c.beginPath(); c.arc(p.x, p.y, r + 5 * U, a0 + (z[0] / 1.1) * Math.PI * 2, a0 + (z[1] / 1.1) * Math.PI * 2); c.stroke();
        c.lineWidth = 3.2 * U;
        c.strokeStyle = pt.tight ? COL.amberHi : pt.done ? COL.tealHi : '#fff';
        c.beginPath(); c.arc(p.x, p.y, r, a0, a0 + clamp(pt.f / 1.1, 0, 1) * Math.PI * 2); c.stroke();
        c.fillStyle = pt.done ? (pt.tight ? COL.amberHi : COL.tealHi) : blocked ? 'rgba(255,255,255,.45)' : '#fff';
        c.font = `700 ${Math.round(10 * U)}px "JetBrains Mono", monospace`;
        c.textAlign = 'center'; c.textBaseline = 'middle';
        c.fillText(pt.tight ? '!' : pt.done ? '✓' : String(i + 1), p.x, p.y + 0.5 * U);
        c.restore();
        if (shapeMode && i === next && S.press < 0) {
          const ring = r + 11 * U + Math.sin(now / 220) * 2 * U;
          c.save(); c.strokeStyle = 'rgba(255,255,255,.6)'; c.lineWidth = 1.4 * U; c.setLineDash([3 * U, 3 * U]);
          c.beginPath(); c.arc(p.x, p.y, ring, 0, Math.PI * 2); c.stroke(); c.restore();
          tags.shape = { at: p, label: blocked ? T('tag_pad_first', 'Pad first') : T('tag_shape', 'Press & hold'), tone: blocked ? 'amber' : 'teal', off: ring + 18 * U, dir: mul(g.m, S.side) };
        }
        if (S.press === i) tags.shape = { at: p, label: `${Math.round(Math.min(1.1, pt.f) * 100)}%`, tone: pt.f > z[1] ? 'amber mono' : pt.f >= z[0] ? 'ok mono' : 'mono', off: r + 22 * U, dir: mul(g.m, S.side) };
      });
    },

    drawStep3(f, g, now, tags) {
      const c = this.oc, U = this.U, S = this.S, t = this.tune;
      const z = t.strapZone;
      const sw = STRAP_W[this.kind];
      let next = -1;
      S.straps.forEach((s, i) => { if (next < 0 && s.state === 'open') next = i; });
      S.straps.forEach((s, i) => {
        const half = this.size.width / 2 + 0.025;
        if (s.state === 'open') {
          const a = this.world(g, s.x - sw / 2, -half), b = this.world(g, s.x + sw / 2, -half), cc = this.world(g, s.x + sw / 2, half), d = this.world(g, s.x - sw / 2, half);
          c.save();
          c.setLineDash([4 * U, 3 * U]); c.lineDashOffset = -now / 70;
          c.strokeStyle = i === next ? 'rgba(255,255,255,.95)' : 'rgba(255,255,255,.4)'; c.lineWidth = 1.5 * U;
          c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 4 * U;
          c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.lineTo(cc.x, cc.y); c.lineTo(d.x, d.y); c.closePath(); c.stroke();
          c.restore();
          if (i === next && S.sweeping < 0) tags.strap = { at: this.world(g, s.x, S.side * half), label: T('tag_strap', 'Strap %s · wrap', i + 1), tone: 'teal', off: 14 * U, dir: mul(g.m, S.side) };
        }
        if (s.state === 'locked' && s.tight && S.cms.state === 'bad') {
          const p = this.world(g, s.x, 0);
          c.save();
          c.strokeStyle = `rgba(229,72,77,${0.55 + 0.45 * Math.sin(now / 160)})`; c.lineWidth = 3 * U;
          c.shadowColor = 'rgba(229,72,77,.8)'; c.shadowBlur = 12 * U;
          const a = this.world(g, s.x - sw / 2 - 0.008, -half), b = this.world(g, s.x + sw / 2 + 0.008, -half), cc = this.world(g, s.x + sw / 2 + 0.008, half), d = this.world(g, s.x - sw / 2 - 0.008, half);
          c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.lineTo(cc.x, cc.y); c.lineTo(d.x, d.y); c.closePath(); c.stroke();
          c.restore();
          tags[`loosen${i}`] = { at: this.world(g, s.x, S.side * half), label: T('tag_loosen', 'Loosen strap %s', i + 1), tone: 'red', off: 14 * U, dir: mul(g.m, S.side) };
          void p;
        }
        // tension gauge beside the strap
        if (s.state === 'sweep') {
          const base = this.world(g, s.x, S.side * (half + 0.02));
          const gh = Math.max(96 * U, 0.15 * g.ppm), gw = 11 * U;
          const gp = add(base, mul(g.m, S.side * (gw + 16 * U)));
          c.save();
          c.translate(gp.x, gp.y);
          c.fillStyle = 'rgba(12,13,16,.9)'; c.strokeStyle = 'rgba(255,255,255,.14)'; c.lineWidth = 1 * U;
          c.beginPath(); if (c.roundRect) c.roundRect(-gw / 2 - 5 * U, -gh / 2 - 5 * U, gw + 10 * U, gh + 10 * U, 7 * U); else c.rect(-gw / 2 - 5 * U, -gh / 2 - 5 * U, gw + 10 * U, gh + 10 * U);
          c.fill(); c.stroke();
          c.fillStyle = 'rgba(255,255,255,.08)'; c.fillRect(-gw / 2, -gh / 2, gw, gh);
          const yOf = tv => gh / 2 - tv * gh;
          c.fillStyle = 'rgba(8,175,162,.45)'; c.fillRect(-gw / 2, yOf(z[1]), gw, (z[1] - z[0]) * gh);
          c.fillStyle = 'rgba(229,72,77,.45)'; c.fillRect(-gw / 2, -gh / 2, gw, (1 - t.strapTight) * gh);
          c.fillStyle = 'rgba(255,255,255,.35)';
          for (let i = 0; i <= 10; i++) { const ty = yOf(i / 10); c.fillRect(gw / 2 + 2 * U, ty - 0.5 * U, (i % 5 ? 3 : 6) * U, 1 * U); }
          c.fillStyle = COL.tealHi; [z[0], z[1]].forEach(zv => c.fillRect(-gw / 2 - 3 * U, yOf(zv) - 0.75 * U, gw + 6 * U, 1.5 * U));
          const ny = yOf(s.tension);
          const inZone = s.tension >= z[0] && s.tension <= z[1];
          c.fillStyle = s.tension > t.strapTight ? COL.redHi : inZone ? COL.tealHi : '#fff';
          c.shadowColor = c.fillStyle; c.shadowBlur = 8 * U;
          c.fillRect(-gw / 2 - 5 * U, ny - 1.8 * U, gw + 10 * U, 3.6 * U);
          c.restore();
          tags.tension = { at: base, label: inZone ? T('tag_cinch', 'Click to cinch') : s.tension > t.strapTight ? T('tag_tight', 'Too tight') : T('tag_tension', 'Tension'), tone: inZone ? 'teal' : s.tension > t.strapTight ? 'red' : '', off: gw * 2 + 40 * U, dir: mul(g.m, S.side) };
        }
      });
      // distal check target
      if (S.cms.state !== 'hidden') {
        const cp = this.cmsPos(f, g);
        const pulse = S.cms.state === 'ready' || S.cms.state === 'bad' ? Math.sin(now / 200) * 2.5 * U : 0;
        const r = 14 * U + pulse;
        const tone = S.cms.state === 'bad' ? COL.red : S.cms.state === 'ok' ? COL.teal : COL.tealHi;
        c.save();
        c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 8 * U;
        this.diamond(c, cp.x, cp.y, r);
        c.fillStyle = S.cms.state === 'bad' ? 'rgba(229,72,77,.3)' : 'rgba(8,175,162,.28)'; c.fill();
        c.lineWidth = 2.2 * U; c.strokeStyle = tone; c.stroke();
        c.shadowBlur = 0;
        if (S.cms.state === 'ready' || S.cms.state === 'bad') {
          const k = (now / 1100) % 1;
          c.globalAlpha = 1 - k; c.lineWidth = 1.6 * U;
          this.diamond(c, cp.x, cp.y, r + k * 20 * U); c.stroke();
        }
        if (S.cms.state === 'checking') {
          const k = clamp((now - S.cms.t) / 1000 / ((S.cms.refill || 1.4) * 1.8 + 0.4), 0, 1);
          c.globalAlpha = 1; c.strokeStyle = COL.tealHi; c.lineWidth = 3 * U; c.lineCap = 'round';
          c.beginPath(); c.arc(cp.x, cp.y, r + 8 * U, -Math.PI / 2, -Math.PI / 2 + k * Math.PI * 2); c.stroke();
        }
        c.restore();
        const where = (this.d.joints && this.d.joints.cms) || (this.kind === 'leg' ? T('toes', 'toes') : T('fingers', 'fingers'));
        if (S.cms.state === 'ready' || S.cms.state === 'bad') tags.cms = { at: cp, label: S.cms.state === 'bad' ? T('tag_recheck', 'Check again') : T('tag_cms', 'Check the %s', where), tone: S.cms.state === 'bad' ? 'red' : 'teal', off: r + 14 * U, dir: mul(g.m, S.side) };
      }
    },

    /* DOM label chips that follow canvas points */
    syncTags(want) {
      const W = this.over.width, H = this.over.height;
      Object.keys(this.tags).forEach(k => { if (!want[k]) { this.tags[k].el.remove(); delete this.tags[k]; } });
      Object.entries(want).forEach(([k, o]) => {
        let t = this.tags[k];
        if (!t) {
          t = { el: NZA.el('div', 'sp-tag') };
          this.tagsEl.appendChild(t.el);
          this.tags[k] = t;
        }
        const sig = `${o.label}|${o.sub || ''}|${o.tone || ''}`;
        if (t.sig !== sig) {
          const tone = o.tone || '';
          if (!t.lbl) { t.lbl = NZA.el('span', 'lbl'); t.el.appendChild(t.lbl); }
          t.lbl.className = `lbl ${tone}`;
          t.lbl.innerHTML = `${/\bok\b/.test(tone) && !/mono/.test(tone) ? icon('check') : ''}<span class="tx">${esc(o.label)}${o.sub ? `<small>${esc(o.sub)}</small>` : ''}</span>`;
          t.sig = sig;
        }
        let ux = 1, uy = 0;
        if (o.dir) { const l = len(o.dir) || 1; ux = o.dir.x / l; uy = o.dir.y / l; }
        const x = o.at.x + ux * (o.off || 0), y = o.at.y + uy * (o.off || 0);
        t.el.style.left = `${(x / W) * 100}%`;
        t.el.style.top = `${(y / H) * 100}%`;
        t.el.classList.toggle('center', !!o.center);
        t.el.classList.toggle('left', !o.center && ux < -0.35);
        t.el.classList.toggle('mid', !o.center && Math.abs(ux) <= 0.35);
        t.el.classList.toggle('up', !o.center && Math.abs(ux) <= 0.35 && uy < 0);
      });
    },

    /* ═════════════════════ MOBILITY CARD ═════════════════════
       Bottom-right card while driving / pushing a wheelchair or walking on crutches.
       chair / push: { kind, title, sub, state ('drive'|'blocked'|'pushed'|'push'), speed (m/s, signed), max,
                       slope (deg, + = uphill), turn (-1..1), dist (m), blocked (text), keys }
       crutch:       { kind, title, sub, state ('walk'|'stand'|'vehicle'), moving, steps, side ('l'|'r'|nil), keys } */
    hudShow(h) {
      const kind = h.kind || (this.hud && this.hud.kind) || 'chair';
      if (!this.hud || this.hud.kind !== kind) this.hud = { kind };
      Object.assign(this.hud, h, { kind });
      if (this.hudKind !== kind || !this.hudEl.firstChild) this.hudBuild(kind);
      this.hudUpdate();
      this.hudEl.hidden = false;
      this.hudEl.classList.toggle('away', !!this.S);
      if (!this.hudRaf) { this.hudLast = 0; this.hudRaf = requestAnimationFrame(this.hudTick); }
    },
    hudHide() {
      this.hud = null;
      this.hudKind = null;
      this.hudEl.hidden = true;
      this.hudEl.innerHTML = '';
      if (this.hudRaf) { cancelAnimationFrame(this.hudRaf); this.hudRaf = 0; }
    },

    // top view of the chair (front up): tyres with moving tread, per-wheel drive bars, casters,
    // footplates, the heading arrow, and the person pushing when kind = push
    chairSVG(push) {
      const tread = side => {
        let l = '';
        for (let y = -6; y <= 72; y += 6) l += `<line x1="${side ? 99 : 11}" y1="${y}" x2="${side ? 109 : 21}" y2="${y + 2}"/>`;
        return `<g clip-path="url(#sph-w${side})"><g class="tread t${side}">${l}</g></g>`;
      };
      return `<svg viewBox="0 0 120 ${push ? 156 : 132}">
        <defs>
          <clipPath id="sph-w0"><rect x="10" y="54" width="12" height="64" rx="5"/></clipPath>
          <clipPath id="sph-w1"><rect x="98" y="54" width="12" height="64" rx="5"/></clipPath>
          <linearGradient id="sph-seat" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#22272c"/><stop offset=".5" stop-color="#30363c"/><stop offset="1" stop-color="#22272c"/></linearGradient>
          <radialGradient id="sph-sh" cx=".5" cy=".55" r=".5"><stop offset="0" stop-color="rgba(0,0,0,.55)"/><stop offset="1" stop-color="rgba(0,0,0,0)"/></radialGradient>
        </defs>
        <ellipse cx="60" cy="78" rx="58" ry="56" fill="url(#sph-sh)"/>
        <g class="arrow"><path class="ar" d="M60 4 L68 14 L63 14 L63 22 L57 22 L57 14 L52 14 Z"/></g>
        <g class="turn"><path class="tl" d="M30 30 A36 36 0 0 1 60 18"/><path class="tr" d="M90 30 A36 36 0 0 0 60 18"/></g>
        <path class="frame" d="M34 58 L40 26 M86 58 L80 26 M40 26 L80 26"/>
        <rect class="foot" x="40" y="20" width="17" height="8" rx="2"/><rect class="foot" x="63" y="20" width="17" height="8" rx="2"/>
        <g class="caster"><rect x="30" y="38" width="6" height="11" rx="3"/><rect x="84" y="38" width="6" height="11" rx="3"/></g>
        <rect class="tyre" x="10" y="54" width="12" height="64" rx="5"/><rect class="tyre" x="98" y="54" width="12" height="64" rx="5"/>
        ${tread(0)}${tread(1)}
        <rect class="rim" x="6" y="58" width="2.2" height="56" rx="1.1"/><rect class="rim" x="111.8" y="58" width="2.2" height="56" rx="1.1"/>
        <rect class="bar b0" x="14.5" y="86" width="3" height="0" rx="1.5"/><rect class="bar b1" x="102.5" y="86" width="3" height="0" rx="1.5"/>
        <rect class="arm" x="26" y="62" width="6" height="34" rx="2.5"/><rect class="arm" x="88" y="62" width="6" height="34" rx="2.5"/>
        <rect x="32" y="56" width="56" height="54" rx="7" fill="url(#sph-seat)" stroke="rgba(255,255,255,.12)"/>
        <path class="stitch" d="M37 61 H83 V105 H37 Z"/>
        <circle class="occ" cx="60" cy="86" r="${push ? 13 : 0}"/>
        <rect class="back" x="30" y="108" width="60" height="9" rx="3"/>
        <circle class="hdl" cx="31" cy="122" r="3.4"/><circle class="hdl" cx="89" cy="122" r="3.4"/>
        ${push ? `<g class="pusher"><path d="M31 123 L44 140 M89 123 L76 140"/><ellipse cx="60" cy="144" rx="19" ry="8"/><circle cx="60" cy="144" r="7.5"/></g>` : ''}
        <g class="blk"><rect x="38" y="0" width="44" height="6" rx="3"/></g>
      </svg>`;
    },
    // top view of the crutch gait (forward = up): both forearm crutches (rubber tip, shaft, grip, cuff),
    // the good foot that swings through, the splinted / broken foot held off the ground (dashed, lifted
    // shadow), the prints already left behind, and scrolling crutch lanes while walking
    crutchSVG(side) {
      const foot = (x, y, cls, flip) => {
        const m = flip ? -1 : 1;
        return `<g class="${cls}" transform="translate(${x} ${y}) scale(${m} 1)">
          <path class="sole" d="M0 0 c-5.4 0 -7.4 -8.4 -6.6 -15.2 c.8 -6.6 3.2 -10.6 6.6 -10.6 c3.6 0 5.8 4.2 6.4 10.6 c.7 7 -1 15.2 -6.4 15.2 z"/>
          <path class="ftr" d="M-4.4 -19 h8.6 M-5 -15 h10 M-5 -11 h10 M-4.2 -3.4 h8.2 M-3.4 -.6 h6.6"/>
        </g>`;
      };
      // a forearm crutch seen from above, tilted forward: tip on the ground, cuff at the forearm
      const crutch = (tx, ty, cx, cy, cls) => `<g class="cr ${cls}">
          <ellipse class="tsh" cx="${tx + 1.5}" cy="${ty + 2}" rx="5.5" ry="3"/>
          <line class="shaft" x1="${tx}" y1="${ty}" x2="${cx}" y2="${cy}"/>
          <line class="shaft hi" x1="${tx - 0.5}" y1="${ty}" x2="${cx - 0.5}" y2="${cy}"/>
          <line class="grip" x1="${cx + (cx < 55 ? 7 : -7)}" y1="${cy - 4}" x2="${cx}" y2="${cy - 1}"/>
          <path class="cuff" d="M${cx - 4.5} ${cy + 5} a5 5 0 0 1 9 0"/>
          <circle class="tip" cx="${tx}" cy="${ty}" r="4.2"/>
        </g>`;
      const hurt = side === 'l' || side === 'r';
      const gx = side === 'l' ? 66 : 44, hx = side === 'l' ? 44 : 66;
      const flipG = gx < 55, flipH = hx < 55;
      return `<svg viewBox="0 0 110 140">
        <defs>
          <radialGradient id="sph-csh" cx=".5" cy=".55" r=".5"><stop offset="0" stop-color="rgba(0,0,0,.5)"/><stop offset="1" stop-color="rgba(0,0,0,0)"/></radialGradient>
          <linearGradient id="sph-fade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".7" stop-color="#fff" stop-opacity=".9"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
          <mask id="sph-cmask"><rect x="0" y="0" width="110" height="140" fill="url(#sph-fade)"/></mask>
        </defs>
        <ellipse cx="55" cy="74" rx="52" ry="64" fill="url(#sph-csh)"/>
        <g mask="url(#sph-cmask)">
          <path class="lane" d="M24 2 V138 M86 2 V138"/>
          <g class="trail">${foot(gx, 138, 'ft old', flipG)}
            <circle class="old-tip" cx="24" cy="100" r="2.4"/><circle class="old-tip" cx="86" cy="100" r="2.4"/>
            <circle class="old-tip o2" cx="24" cy="134" r="2.4"/><circle class="old-tip o2" cx="86" cy="134" r="2.4"/></g>
        </g>
        <path class="fwd" d="M55 2 L61 10 L57 10 L57 18 L53 18 L53 10 L49 10 Z"/>
        <g class="tips ph-a">${crutch(24, 30, 33, 58, 'l')}${crutch(86, 30, 77, 58, 'r')}</g>
        <g class="tips ph-b">${crutch(24, 66, 33, 92, 'l')}${crutch(86, 66, 77, 92, 'r')}</g>
        <path class="swing" d="M${gx} 98 C${gx} 86 ${gx} 78 ${gx} 70"/>
        <g class="good ph-a">${foot(gx, 70, 'ft', flipG)}</g>
        <g class="good ph-b">${foot(gx, 104, 'ft', flipG)}</g>
        ${hurt
          ? `<g class="hurt"><ellipse class="hov" cx="${hx + 2}" cy="${94}" rx="7.5" ry="13" /><g class="lift">${foot(hx, 98, 'ft nwb', flipH)}</g>
             <text class="nwbt" x="${hx}" y="114" text-anchor="middle">${esc(T('hud_nwb', 'NWB'))}</text></g>`
          : `<g class="good ph-a">${foot(hx, 70, 'ft', flipH)}</g><g class="good ph-b">${foot(hx, 104, 'ft', flipH)}</g>`}
      </svg>`;
    },
    hudBuild(kind) {
      const el = this.hudEl;
      this.hudKind = kind;
      this.hudRefs = {};
      el.className = `sp-hud nza-hud solid kind-${kind}`;
      const R = this.hudRefs;
      if (kind === 'crutch') {
        el.innerHTML = `
          <div class="hh"><span class="kick">${icon('crutch')}<span class="kt"></span></span><span class="chipx sm st"></span></div>
          <div class="hm">
            <div class="viz"></div>
            <div class="ins">
              <div class="ttl"></div><div class="sub"></div>
              <div class="row"><span>${esc(T('hud_steps', 'Steps'))}</span><span class="odo-h steps"></span></div>
              <div class="row"><span>${esc(T('hud_cadence', 'Cadence'))}</span><b class="cad"></b><em>${esc(T('hud_per_min', '/min'))}</em></div>
              <div class="row"><span>${esc(T('hud_weight', 'Weight on'))}</span><b class="wt"></b></div>
              <div class="row"><span>${esc(T('hud_pace', 'Pace'))}</span><b class="pace"></b></div>
            </div>
          </div>
          <div class="gait">
            <span class="gs" data-i="0"><i>1</i><em>${esc(T('hud_gait_0', 'Tips ahead'))}</em></span>
            <span class="gs" data-i="1"><i>2</i><em>${esc(T('hud_gait_1', 'Swing'))}</em></span>
            <span class="gs" data-i="2"><i>3</i><em>${esc(T('hud_gait_2', 'Plant'))}</em></span>
            <b class="gbar"><u></u></b>
          </div>
          <div class="keys"></div>`;
        R.steps = NZA.ui.FlipClock(el.querySelector('.steps'), { value: '000', small: true });
      } else {
        el.innerHTML = `
          <div class="hh"><span class="kick">${icon(kind === 'push' ? 'hand' : 'wheelchair')}<span class="kt"></span></span><span class="chipx sm st"></span></div>
          <div class="hm">
            <div class="viz">${this.chairSVG(kind === 'push')}</div>
            <div class="ins">
              <div class="ttl"></div><div class="sub"></div>
              <div class="row big"><span>${esc(T('hud_speed', 'Speed'))}</span><span class="odo-h spd"></span><em>${esc(T('kmh', 'km/h'))}</em></div>
              <div class="meter"><i class="mf"></i><i class="mz"></i></div>
              <div class="row"><span>${esc(T('grade_lbl', 'Grade'))}</span><span class="incl"><i></i></span><b class="gr"></b></div>
              <div class="row"><span>${esc(T('hud_dist', 'Travelled'))}</span><span class="odo-h dist"></span><em>m</em></div>
            </div>
          </div>
          <div class="note"><span class="ni">${icon('alert')}</span><span class="nt"></span><i class="nb"></i></div>
          <div class="keys"></div>`;
        R.spd = NZA.ui.FlipClock(el.querySelector('.spd'), { value: '0.0', small: true });
        R.dist = NZA.ui.FlipClock(el.querySelector('.dist'), { value: '0000', small: true });
      }
      R.svg = el.querySelector('.viz svg');
      R.kt = el.querySelector('.kt'); R.st = el.querySelector('.st');
      R.ttl = el.querySelector('.ttl'); R.sub = el.querySelector('.sub'); R.keys = el.querySelector('.keys');
      R.treads = [...el.querySelectorAll('.tread')];
      R.bars = [...el.querySelectorAll('.bar')];
      R.off = [0, 0]; R.ph = 0;
    },
    hudUpdate() {
      const o = this.hud, R = this.hudRefs, el = this.hudEl;
      if (!o || !R) return;
      const kind = o.kind;
      R.ttl.textContent = o.title || '';
      R.sub.textContent = o.sub || '';
      const keys = (o.keys || []).map(k => `<span class="hk">${(k.keys || []).map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(k.label)}</em></span>`).join('');
      if (R.keysHtml !== keys) { R.keys.innerHTML = keys; R.keysHtml = keys; R.keys.style.display = keys ? '' : 'none'; }
      if (kind === 'crutch') {
        R.kt.textContent = T('hud_kicker_mob', 'Mobility aid');
        const st = o.state || (o.moving ? 'walk' : 'stand');
        R.st.textContent = st === 'vehicle' ? T('hud_st_vehicle', 'Stowed') : o.moving ? T('hud_st_walk', 'Walking') : T('hud_st_stand', 'Standing');
        R.st.className = `chipx sm st ${o.moving ? 'teal' : ''}`;
        const steps = Math.max(0, Math.floor(Number(o.steps) || 0));
        R.steps.set(String(Math.min(999, steps)).padStart(3, '0'));
        // cadence: steps per minute over the last ~8 s of samples (or the value the client sends)
        const now = performance.now();
        R.hist = (R.hist || []).filter(h => now - h.t < 8000 && h.s <= steps);
        R.hist.push({ t: now, s: steps });
        let cad = Number(o.cadence);
        if (!Number.isFinite(cad)) {
          const a = R.hist[0], b = R.hist[R.hist.length - 1];
          cad = o.moving && b.t - a.t > 1500 ? (b.s - a.s) / ((b.t - a.t) / 60000) : 0;
        }
        R.cad = o.moving ? (R.cad ? R.cad + (cad - R.cad) * 0.35 : cad) : 0;
        el.querySelector('.cad').textContent = o.moving && R.cad > 0.5 ? String(Math.round(R.cad)) : '--';
        el.querySelector('.wt').textContent = o.side === 'l' ? T('hud_w_right', 'Right leg only') : o.side === 'r' ? T('hud_w_left', 'Left leg only') : T('hud_w_both', 'Both legs, light');
        el.querySelector('.pace').textContent = st === 'vehicle' ? '--' : o.moving ? T('hud_pace_walk', 'Walk · no running') : T('hud_pace_rest', 'Resting');
        const side = o.side === 'l' || o.side === 'r' ? o.side : '';
        if (R.side !== side || !R.svg) { R.side = side; const v = el.querySelector('.viz'); v.innerHTML = this.crutchSVG(side); R.svg = v.querySelector('svg'); }
        el.classList.toggle('moving', !!o.moving);
        if (!o.moving) delete el.dataset.ph;
        return;
      }
      const speed = Number(o.speed) || 0, max = Math.max(0.1, Number(o.max) || 2);
      const slope = Number(o.slope) || 0, turn = clamp(Number(o.turn) || 0, -1, 1);
      const blocked = !!o.blocked;
      R.kt.textContent = kind === 'push' ? T('hud_kicker_push', 'Pushing') : T('hud_kicker_chair', 'Wheelchair');
      const stKey = blocked ? 'blocked' : o.state === 'pushed' ? 'pushed' : Math.abs(speed) > 0.05 ? (speed > 0 ? 'rolling' : 'reverse') : 'parked';
      R.st.textContent = { blocked: T('hud_st_blocked', 'Blocked'), pushed: T('hud_st_pushed', 'Being pushed'), rolling: T('hud_rolling', 'Rolling'), reverse: T('hud_reversing', 'Reversing'), parked: T('hud_parked', 'Parked') }[stKey];
      R.st.className = `chipx sm st ${stKey === 'blocked' ? 'amber' : stKey === 'rolling' ? 'teal' : ''}`;
      R.spd.set((Math.abs(speed) * 3.6).toFixed(1));
      R.spd.tone(blocked ? 'amber' : speed < -0.05 ? 'amber' : '');
      R.dist.set(String(Math.min(9999, Math.max(0, Math.floor(Number(o.dist) || 0)))).padStart(4, '0'));
      const f = clamp(Math.abs(speed) / max, 0, 1);
      el.querySelector('.mf').style.width = `${(f * 100).toFixed(1)}%`;
      el.querySelector('.mf').classList.toggle('rev', speed < -0.05);
      el.querySelector('.incl i').style.transform = `rotate(${clamp(-slope, -30, 30).toFixed(1)}deg)`;
      const steep = Math.abs(slope) >= 8;
      const gr = el.querySelector('.gr');
      gr.textContent = `${slope > 0.5 ? '▲' : slope < -0.5 ? '▼' : '='} ${Math.abs(slope).toFixed(0)}°`;
      gr.className = `gr ${steep ? 'amber' : ''}`;
      el.querySelector('.nt').textContent = o.blocked || '';
      el.classList.toggle('blocked', blocked);
      el.classList.toggle('rev', speed < -0.05);
      el.classList.toggle('moving', Math.abs(speed) > 0.05);
      el.classList.toggle('turn-l', turn > 0.2);
      el.classList.toggle('turn-r', turn < -0.2);
      // per-wheel drive bars (rim speed): turning on the spot drives the wheels against each other
      const vL = speed - turn * 0.55, vR = speed + turn * 0.55;
      R.bars.forEach((b, i) => {
        const vv = i === 0 ? vL : vR, hgt = clamp(Math.abs(vv) / max, 0, 1) * 28;
        b.setAttribute('y', vv >= 0 ? 86 - hgt : 86);
        b.setAttribute('height', hgt.toFixed(1));
        b.setAttribute('class', `bar b${i} ${vv < -0.02 ? 'rev' : ''}`);
      });
      const ar = R.svg.querySelector('.arrow');
      ar.setAttribute('transform', `translate(0 ${(-(f) * 3).toFixed(1)}) ${speed < -0.05 ? 'rotate(180 60 66)' : ''}`);
      R.vL = vL; R.vR = vR;
    },
    hudTick(now) {
      this.hudRaf = 0;
      if (!this.hud || this.hudEl.hidden) return;
      const dt = Math.min(0.1, this.hudLast ? (now - this.hudLast) / 1000 : 0);
      this.hudLast = now;
      const R = this.hudRefs;
      if (R && !this.reduced) {
        if (this.hud.kind === 'crutch') {
          if (this.hud.moving) {
            R.ph = (R.ph + dt / 0.55) % 3;
            const p = Math.floor(R.ph);
            if (p !== R.lastPh) { R.lastPh = p; this.hudEl.dataset.ph = String(p); }
          }
        } else if (R.treads.length) {
          // tread scrolls with each wheel's rim speed (px per metre on the drawing)
          [R.vL || 0, R.vR || 0].forEach((vv, i) => {
            R.off[i] = (R.off[i] - vv * dt * 26) % 6;
            R.treads[i].setAttribute('transform', `translate(0 ${(R.off[i] < 0 ? R.off[i] + 6 : R.off[i]).toFixed(2)})`);
          });
        }
      }
      // keep animating only while something moves (hudShow restarts it)
      const moving = this.hud.kind === 'crutch' ? !!this.hud.moving : (R && (Math.abs(R.vL || 0) > 0.01 || Math.abs(R.vR || 0) > 0.01));
      if (moving && !this.reduced) this.hudRaf = requestAnimationFrame(this.hudTick);
      else this.hudLast = 0;
    },

    /* ═════════════════════ PREVIEW ═════════════════════ */
    preview(stage) {
      stage = stage || new URLSearchParams(location.search).get('stage') || 'place';
      if (!this._world && this._world !== null) { setTimeout(() => this.previewRun(stage), 30); return; }
      this.previewRun(stage);
    },
    previewRun(stage) {
      LOC = {};
      const W = previewWorld(this);
      const arm = stage === 'arm' || stage.startsWith('arm-');
      NZA.mock(`${APP}:finish`, r => ({ ok: true, outcome: { score: r.score, grade: r.score >= 90 ? 'S' : r.score >= 80 ? 'A' : r.score >= 68 ? 'B' : 'C', msg: arm ? 'Right forearm splinted · pain easing' : 'Right lower leg splinted · pain easing' } }));
      if (stage.startsWith('hud')) {
        this.procStop();
        if (W) { W.body(false); W.view('third'); W.tick(); }
        const drive = [{ keys: ['W', 'S'], label: 'Drive' }, { keys: ['A', 'D'], label: 'Turn' }, { keys: ['F'], label: 'Stand up' }];
        const hudDemo = {
          'hud-chair': { kind: 'chair', title: 'Self-propelled', sub: 'Rims under both hands', state: 'drive', speed: 1.42, max: 1.9, slope: -4, turn: 0.35, dist: 126, keys: drive },
          'hud-blocked': { kind: 'chair', title: 'Self-propelled', sub: 'Back off and find a ramp', state: 'blocked', blocked: 'Curb too high', speed: 0, max: 1.9, slope: 2, turn: 0, dist: 131, keys: drive },
          'hud-push': { kind: 'push', title: 'Pushing a wheelchair', sub: 'Michael Garcia', state: 'push', speed: 1.1, max: 1.9, slope: 6, turn: 0, dist: 48, keys: [{ keys: ['G'], label: 'Let go' }] },
          'hud-crutch': { kind: 'crutch', title: 'On crutches', sub: 'Splinted right lower leg', state: 'walk', moving: true, steps: 37, cadence: 46, side: 'r', keys: [{ keys: ['/crutches'], label: 'Put away' }] },
        }[stage] || {};
        NZA.demo(APP, { mode: 'hud', hud: hudDemo });
        if (stage === 'hud-crutch') this.hudEl.dataset.ph = '1';
        return;
      }
      if (W) W.view(arm ? 'arm' : 'leg');
      const J = W ? W.joints(arm) : null;
      const d = arm ? {
        mode: 'proc', region: 'r_lower_arm', regionLabel: 'Right forearm', limb: 'arm', device: 'arm', segment: 'lower',
        deviceLabel: 'Contour arm splint', deviceModel: 'CS-40',
        joints: { prox: 'Elbow', dist: 'Wrist', cms: 'fingers', proxKey: 'elbow', distKey: 'wrist', cmsKey: 'fingers' },
        fracture: { kind: 'closed', kindLabel: 'Closed fracture', bone: 'radius_ulna', boneLabel: 'Radius and ulna', displaced: false, angle: 0, at: 0.62 },
        open: false, severity: 2, pulse: 'present', hr: 96, sys: 128, refill: 1.4, responsive: true, name: 'Michael Garcia', pain: 64,
        size: { width: 0.105, depth: 0.05, wall: 0.008, limbRadius: 0.04 }, segLen: J ? J.segLen : 0.26, fov: 50,
      } : {
        mode: 'proc', region: 'r_lower_leg', regionLabel: 'Right lower leg', limb: 'leg', device: 'leg', segment: 'lower',
        deviceLabel: 'Contour leg splint', deviceModel: 'CS-76',
        joints: { prox: 'Knee', dist: 'Ankle', cms: 'toes', proxKey: 'knee', distKey: 'ankle', cmsKey: 'toes' },
        fracture: { kind: 'closed', kindLabel: 'Closed fracture', bone: 'tibia_fibula', boneLabel: 'Tibia and fibula', displaced: true, angle: 14, at: 0.52 },
        open: false, severity: 3, pulse: 'present', hr: 104, sys: 122, refill: 1.4, responsive: true, name: 'Michael Garcia', pain: 72,
        size: { width: 0.15, depth: 0.07, wall: 0.01, limbRadius: 0.055 }, segLen: J ? J.segLen : 0.43, fov: 50,
      };
      d.keys = { rotateLeft: 'KeyQ', rotateRight: 'KeyE', reset: 'KeyX', set: 'Space' };
      NZA.demo(APP, d);
      this.previewStage(stage.replace(/^arm-?/, '') || 'place');
    },
    // Puts the running procedure straight into a stage (synchronous - software WebGL frames are slow,
    // so timer chains would race the screenshot). Stages: place aligned pad shape strap cmsready cms cmsbad done
    previewStage(st) {
      const S = this.S;
      if (!S) return;
      const order = ['place', 'aligned', 'pad', 'shape', 'strap', 'cmsready', 'cms', 'cmsbad', 'done'];
      const lvl = Math.max(0, order.indexOf(st));
      const now = performance.now();
      S.intro = now - 4000;
      S.t0 = now - 97000;
      S.moved = true;
      if (st === 'aligned') {
        S.pose = { cu: 0.006, cv: 0.004, phi: 0.02 }; S.pose0 = Object.assign({}, S.pose); S.alignHold = -1e9;
        return;
      }
      if (lvl < 2) return;
      // 1 · laid and set
      S.pose = { cu: 0, cv: 0, phi: 0 }; S.pose0 = { cu: 0.04, cv: 0.2, phi: 0.3 };
      S.locked = true; S.aligned = { p: true, d: true }; S.err = { p: 0.006, d: 0.009, a: 0.8 }; S.s1 = 93;
      this.enterStep(2);
      if (st === 'pad') {
        this.padSite(0); S.sites[0].pop = 0;
        return;
      }
      S.sites.forEach(x => { x.padded = true; x.pop = 0; });
      if (st === 'shape') {
        S.tool = 'shape';
        S.points.forEach((p, i) => { if (i < 3) { p.f = [0.84, 0.9, 0.87][i]; p.done = true; } });
        S.points[3].f = 0.61; S.press = 3;
        this._holdPreview = true;
        this.enterStep(2, true); this.refreshTools(); this.updateReadout(true);
        return;
      }
      // 2 · padded and shaped
      S.points.forEach((p, i) => { p.f = [0.84, 0.9, 0.87, 0.92, 0.88, 0.86, 0.9, 0.85, 0.89][i] || 0.86; p.done = true; p.pop = 0; });
      S.shapeDone = true; S.s2 = 91;
      this.enterStep(3);
      if (st === 'strap') {
        const s0 = S.straps[0]; s0.state = 'locked'; s0.k = 1; s0.tension = 0.68; s0.quality = 96;
        const s1 = S.straps[1]; s1.state = 'sweep'; s1.k = 1; s1.ph = 0.19; s1.tension = 0.5 - 0.5 * Math.cos(s1.ph * Math.PI * 2); S.sweeping = 1;
        this.refreshTools(); this.updateReadout(true);
        return;
      }
      // 3 · strapped, distal check
      S.straps.forEach((x, i) => {
        x.state = 'locked'; x.k = 1; x.tension = st === 'cmsbad' && i === 1 ? 0.93 : [0.66, 0.71, 0.64][i];
        x.quality = x.tension > 0.9 ? 30 : [96, 92, 95][i]; x.tight = x.tension > 0.9; if (x.tight) S.tightEver += 1;
      });
      S.cms.state = 'ready'; S.tool = 'cms';
      this.enterStep(3, true); this.refreshTools(); this.updateReadout(true);
      if (st === 'cmsready') return;
      this.cmsCheck();
      if (st === 'cms') { S.cms.t = now - 1500; S.cms.hold = true; return; }
      S.cms.t = now - 60000;            // cmsbad / done: the check has run its course
    },
  };

  /* ═════════════════════ BROWSER PREVIEW WORLD (3D street scene) ═════════════════════ */
  function previewWorld(app) {
    if (app._world !== undefined) return app._world;
    app._world = null;
    if (!window.THREE) return null;
    const cv = document.createElement('canvas');
    cv.className = 'sp-world';
    document.body.prepend(cv);
    let R;
    try { R = new THREE.WebGLRenderer({ canvas: cv, antialias: true }); } catch (e) { cv.remove(); return null; }
    R.setPixelRatio(1);
    R.outputEncoding = THREE.sRGBEncoding;
    R.toneMapping = THREE.ACESFilmicToneMapping;
    R.toneMappingExposure = 1.0;
    R.shadowMap.enabled = true;
    R.shadowMap.type = THREE.PCFSoftShadowMap;
    const scene = new THREE.Scene();
    scene.background = lin('#55585b');
    scene.environment = envTexture(R, { sky: 0xbfd0de, horizon: 0x8a8d8f, ground: 0x3a3a38 });
    const cam = new THREE.PerspectiveCamera(50, 16 / 9, 0.05, 80);
    const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

    // ── lights
    const hemi = new THREE.HemisphereLight(lin('#dfe9f2'), lin('#3b3631'), 0.55); hemi.position.set(0, 0, 1); scene.add(hemi);
    const sun = new THREE.DirectionalLight(lin('#fff0dc'), 2.5);
    sun.position.set(-1.6, 1.5, 3.4); sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048); sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.015;
    Object.assign(sun.shadow.camera, { left: -2.2, right: 2.2, top: 2.2, bottom: -2.2, near: 0.5, far: 9 });
    scene.add(sun); scene.add(sun.target);
    const rim = new THREE.DirectionalLight(lin('#cfe3ff'), 0.35); rim.position.set(1.5, -1, 1.2); scene.add(rim);

    // ── textures
    function asphalt() {
      const n = 1024, r = rng(1234);
      const c = cvs(n, n), x = c.getContext('2d'), h = cvs(n, n), hx = h.getContext('2d');
      x.fillStyle = '#3e4043'; x.fillRect(0, 0, n, n);
      hx.fillStyle = '#7a7a7a'; hx.fillRect(0, 0, n, n);
      for (let i = 0; i < 14; i++) {
        const gx = r() * n, gy = r() * n, gr = 60 + r() * 220;
        const gg = x.createRadialGradient(gx, gy, 0, gx, gy, gr);
        const dark = r() > 0.5;
        gg.addColorStop(0, dark ? 'rgba(20,20,22,.25)' : 'rgba(120,118,112,.16)'); gg.addColorStop(1, 'rgba(0,0,0,0)');
        x.fillStyle = gg; x.fillRect(0, 0, n, n);
      }
      for (let i = 0; i < 90000; i++) {
        const px = r() * n, py = r() * n, s = 0.5 + r() * 1.5, l = 48 + r() * 70;
        x.fillStyle = `rgba(${l},${l},${l - 3},${0.18 + r() * 0.35})`; x.fillRect(px, py, s, s);
        const hl = 100 + r() * 110; hx.fillStyle = `rgb(${hl},${hl},${hl})`; hx.fillRect(px, py, s, s);
      }
      for (let i = 0; i < 2600; i++) {
        const px = r() * n, py = r() * n, s = 1 + r() * 2.2, l = 105 + r() * 50;
        x.fillStyle = `rgba(${l},${l - 2},${l - 6},${0.25 + r() * 0.3})`; x.fillRect(px, py, s, s * (0.6 + r() * 0.6));
      }
      x.strokeStyle = 'rgba(18,18,20,.32)'; hx.strokeStyle = '#4a4a4a';
      for (let k = 0; k < 4; k++) {
        let px = r() * n, py = r() * n; x.lineWidth = hx.lineWidth = 0.8 + r() * 0.8;
        x.beginPath(); hx.beginPath(); x.moveTo(px, py); hx.moveTo(px, py);
        for (let s = 0; s < 26; s++) { px += (r() - 0.5) * 22; py += (r() - 0.3) * 16; x.lineTo(px, py); hx.lineTo(px, py); }
        x.stroke(); hx.stroke();
      }
      const oil = x.createRadialGradient(n * 0.7, n * 0.3, 10, n * 0.7, n * 0.3, 120);
      oil.addColorStop(0, 'rgba(10,10,12,.35)'); oil.addColorStop(1, 'rgba(10,10,12,0)'); x.fillStyle = oil; x.fillRect(0, 0, n, n);
      return { map: tex(c, [4, 4], true), normal: tex(normalFromHeight(h, 1.6), [4, 4]) };
    }
    function denim() {
      const w = 256, hgt = 512, r = rng(77);
      const c = cvs(w, hgt), x = c.getContext('2d'), h = cvs(w, hgt), hx = h.getContext('2d');
      x.fillStyle = '#2c4362'; x.fillRect(0, 0, w, hgt);
      hx.fillStyle = '#808080'; hx.fillRect(0, 0, w, hgt);
      for (let i = -hgt; i < w + hgt; i += 3) {
        x.strokeStyle = i % 6 ? 'rgba(170,190,215,.12)' : 'rgba(10,20,40,.22)'; x.lineWidth = 1.2;
        x.beginPath(); x.moveTo(i, 0); x.lineTo(i + hgt * 0.45, hgt); x.stroke();
        hx.strokeStyle = i % 6 ? '#9a9a9a' : '#5a5a5a'; hx.beginPath(); hx.moveTo(i, 0); hx.lineTo(i + hgt * 0.45, hgt); hx.stroke();
      }
      for (let i = 0; i < 9000; i++) { const l = 120 + r() * 120; x.fillStyle = `rgba(${l - 40},${l - 20},${l},${r() * 0.12})`; x.fillRect(r() * w, r() * hgt, 1 + r() * 2, 1); }
      // wear on the front of the thigh / shin
      [0.25, 0.75].forEach(cy => { const g = x.createRadialGradient(w * 0.5, hgt * cy, 4, w * 0.5, hgt * cy, w * 0.42); g.addColorStop(0, 'rgba(170,190,215,.2)'); g.addColorStop(1, 'rgba(170,190,215,0)'); x.fillStyle = g; x.fillRect(0, 0, w, hgt); });
      // creases
      for (let i = 0; i < 26; i++) {
        const y = r() * hgt, x0 = r() * w;
        hx.strokeStyle = r() > 0.5 ? '#b0b0b0' : '#505050'; hx.lineWidth = 2 + r() * 4;
        hx.beginPath(); hx.moveTo(x0, y); hx.quadraticCurveTo(x0 + 30, y + (r() - 0.5) * 20, x0 + 60 + r() * 60, y + (r() - 0.5) * 12); hx.stroke();
        x.strokeStyle = 'rgba(10,20,40,.12)'; x.lineWidth = 3; x.beginPath(); x.moveTo(x0, y); x.quadraticCurveTo(x0 + 30, y + 4, x0 + 80, y + 2); x.stroke();
      }
      // side seams with topstitching
      [0.0, 0.5].forEach(f => {
        const sx = w * f;
        x.fillStyle = 'rgba(12,20,38,.35)'; x.fillRect(sx, 0, 3, hgt);
        x.fillStyle = 'rgba(190,135,68,.7)';
        for (let y = 0; y < hgt; y += 7) { x.fillRect(sx - 4, y, 1.2, 4); x.fillRect(sx + 6, y + 3, 1.2, 4); }
        hx.fillStyle = '#c0c0c0'; hx.fillRect(sx, 0, 3, hgt);
      });
      return { map: tex(c, [1, 1], true), normal: tex(normalFromHeight(h, 2.2), [1, 1]) };
    }
    function leather(base, seed) {
      const n = 512, r = rng(seed);
      const c = cvs(n, n), x = c.getContext('2d'), h = cvs(n, n), hx = h.getContext('2d');
      x.fillStyle = base; x.fillRect(0, 0, n, n); hx.fillStyle = '#808080'; hx.fillRect(0, 0, n, n);
      for (let i = 0; i < 26000; i++) { const px = r() * n, py = r() * n, s = 1 + r() * 2.5, l = r(); x.fillStyle = `rgba(${l > 0.5 ? 255 : 0},${l > 0.5 ? 240 : 0},${l > 0.5 ? 230 : 0},${0.02 + r() * 0.03})`; x.fillRect(px, py, s, s); hx.fillStyle = `rgba(${l > 0.5 ? 255 : 0},${l > 0.5 ? 255 : 0},${l > 0.5 ? 255 : 0},.2)`; hx.fillRect(px, py, s, s); }
      for (let i = 0; i < 40; i++) { const y = r() * n; hx.strokeStyle = 'rgba(40,40,40,.6)'; hx.lineWidth = 1 + r() * 2; hx.beginPath(); hx.moveTo(r() * n, y); hx.quadraticCurveTo(r() * n, y + (r() - 0.5) * 60, r() * n, y + (r() - 0.5) * 30); hx.stroke(); }
      return { map: tex(c, [1, 1], true), normal: tex(normalFromHeight(h, 2.8), [1, 1]) };
    }
    function paint() {
      const w = 64, hgt = 1024, r = rng(5);
      const c = cvs(w, hgt), x = c.getContext('2d');
      x.fillStyle = '#e9e6dc'; x.fillRect(0, 0, w, hgt);
      x.globalCompositeOperation = 'destination-out';
      for (let i = 0; i < 1800; i++) { x.fillStyle = `rgba(0,0,0,${0.15 + r() * 0.5})`; x.beginPath(); x.arc(r() * w, r() * hgt, 0.5 + r() * 2.2, 0, Math.PI * 2); x.fill(); }
      return tex(c, [1, 4], true);
    }

    // cotton twill work jacket: diagonal weave, slub noise, soft creases
    function fabric(base, seed) {
      const n = 512, r = rng(seed);
      const c = cvs(n, n), x = c.getContext('2d'), h = cvs(n, n), hx = h.getContext('2d');
      x.fillStyle = base; x.fillRect(0, 0, n, n);
      hx.fillStyle = '#808080'; hx.fillRect(0, 0, n, n);
      for (let i = -n; i < n * 2; i += 3) {
        x.strokeStyle = i % 6 ? 'rgba(255,255,255,.035)' : 'rgba(0,0,0,.12)'; x.lineWidth = 1;
        x.beginPath(); x.moveTo(i, 0); x.lineTo(i - n * 0.6, n); x.stroke();
        hx.strokeStyle = i % 6 ? '#959595' : '#6a6a6a'; hx.beginPath(); hx.moveTo(i, 0); hx.lineTo(i - n * 0.6, n); hx.stroke();
      }
      for (let i = 0; i < 7000; i++) { const l = r() > 0.5; x.fillStyle = l ? `rgba(255,255,255,${r() * 0.05})` : `rgba(0,0,0,${r() * 0.07})`; x.fillRect(r() * n, r() * n, 1 + r() * 3, 1); }
      for (let i = 0; i < 14; i++) {
        const y = r() * n, x0 = r() * n, len = 60 + r() * 140;
        const g = x.createLinearGradient(x0, y - 6, x0, y + 6); g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(0.5, 'rgba(0,0,0,.14)'); g.addColorStop(1, 'rgba(0,0,0,0)');
        x.fillStyle = g; x.fillRect(x0, y - 6, len, 12);
        hx.fillStyle = 'rgba(40,40,40,.5)'; hx.fillRect(x0, y - 2, len, 4);
      }
      return { map: tex(c, [3, 3], true), normal: tex(normalFromHeight(h, 1.8), [3, 3]) };
    }
    const tA = asphalt(), tD = denim(), tJ = fabric('#37414c', 31), tB = leather('#17181a', 47), tG = leather('#1e1f22', 63);
    const mat = {
      ground: new THREE.MeshStandardMaterial({ map: tA.map, normalMap: tA.normal, normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.94, metalness: 0 }),
      paint: new THREE.MeshStandardMaterial({ map: paint(), transparent: true, roughness: 0.7, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }),
      curb: new THREE.MeshStandardMaterial({ color: lin('#8d8c86'), roughness: 0.9, normalMap: tA.normal, normalScale: new THREE.Vector2(0.4, 0.4) }),
      denim: new THREE.MeshStandardMaterial({ map: tD.map, normalMap: tD.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.92 }),
      jacket: new THREE.MeshStandardMaterial({ map: tJ.map, normalMap: tJ.normal, normalScale: new THREE.Vector2(0.7, 0.7), roughness: 0.86, metalness: 0 }),
      tape: new THREE.MeshStandardMaterial({ color: lin('#d7dad6'), roughness: 0.35, metalness: 0.15, envMapIntensity: 1.4 }),
      boot: new THREE.MeshStandardMaterial({ map: tB.map, normalMap: tB.normal, roughness: 0.5, metalness: 0.05 }),
      sole: new THREE.MeshStandardMaterial({ color: lin('#26221f'), roughness: 0.85 }),
      glove: new THREE.MeshStandardMaterial({ map: tG.map, normalMap: tG.normal, roughness: 0.6 }),
      helmet: new THREE.MeshPhysicalMaterial({ color: lin('#1c1e21'), roughness: 0.45, clearcoat: 0.6, clearcoatRoughness: 0.35 }),
      visor: new THREE.MeshPhysicalMaterial({ color: lin('#121820'), roughness: 0.05, metalness: 0.2, clearcoat: 1, transparent: true, opacity: 0.92 }),
      metal: new THREE.MeshStandardMaterial({ color: lin('#a8adb2'), metalness: 0.95, roughness: 0.3 }),
      skin: new THREE.MeshPhysicalMaterial({ color: lin('#9c6248'), roughness: 0.6, sheen: 0.12, sheenColor: lin('#e8b49a'), sheenRoughness: 0.7 }),
      nail: new THREE.MeshStandardMaterial({ color: lin('#b98a7a'), roughness: 0.32 }),
      shard: new THREE.MeshPhysicalMaterial({ color: lin('#c8d8dc'), roughness: 0.05, transmission: 0, metalness: 0.1, clearcoat: 1, transparent: true, opacity: 0.6 }),
      reflector: new THREE.MeshStandardMaterial({ color: lin('#d4601a'), roughness: 0.35, emissive: lin('#3a1004') }),
      leaf: new THREE.MeshStandardMaterial({ color: lin('#7a5a2c'), roughness: 0.9, side: THREE.DoubleSide }),
    };

    // ── ground, paint line, curb, debris
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(9, 9), mat.ground);
    ground.receiveShadow = true; scene.add(ground);
    const line = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 9), mat.paint);
    line.position.set(0.78, 0, 0.001); line.receiveShadow = true; scene.add(line);
    const curb = new THREE.Mesh(new THREE.BoxGeometry(0.32, 9, 0.15), mat.curb);
    curb.position.set(-1.38, 0, 0.075); curb.castShadow = curb.receiveShadow = true; scene.add(curb);
    const gutter = new THREE.Mesh(new THREE.PlaneGeometry(0.28, 9), new THREE.MeshStandardMaterial({ color: lin('#5d5e5c'), roughness: 0.9, normalMap: tA.normal }));
    gutter.position.set(-1.08, 0, 0.0015); gutter.receiveShadow = true; scene.add(gutter);
    const dr = rng(404);
    for (let i = 0; i < 34; i++) {
      const glass = i < 28;
      const g = glass ? new THREE.BoxGeometry(0.004 + dr() * 0.01, 0.003 + dr() * 0.008, 0.0015) : new THREE.BoxGeometry(0.008 + dr() * 0.016, 0.006 + dr() * 0.01, 0.003);
      const m = new THREE.Mesh(g, glass ? mat.shard : mat.reflector);
      m.position.set(0.35 + dr() * 0.55, -1.35 + dr() * 1.1, 0.0015);
      m.rotation.z = dr() * Math.PI; m.castShadow = true; scene.add(m);
    }
    for (let i = 0; i < 6; i++) {
      const lf = new THREE.Mesh(new THREE.CircleGeometry(0.022 + dr() * 0.014, 20), mat.leaf);
      lf.scale.set(1, 0.42, 1); lf.position.set(-1.15 + dr() * 0.3, -1.6 + dr() * 2.4, 0.003); lf.rotation.z = dr() * Math.PI; lf.receiveShadow = true; scene.add(lf);
    }

    // ── patient (supine, head toward +y, patient's right side = -x)
    const body = new THREE.Group(); scene.add(body);
    const J = {
      pelvis: V3(0, 0, 0.12), rHip: V3(-0.095, -0.03, 0.105), lHip: V3(0.095, -0.03, 0.105),
      rKnee: V3(-0.13, -0.46, 0.074), lKnee: V3(0.125, -0.45, 0.078),
      rMid: V3(-0.148, -0.665, 0.064), rAnkle: V3(-0.19, -0.875, 0.058), lAnkle: V3(0.15, -0.87, 0.06),
      chest: V3(0, 0.32, 0.15), rSh: V3(-0.2, 0.47, 0.12), lSh: V3(0.2, 0.47, 0.12),
      rEl: V3(-0.32, 0.23, 0.075), rWr: V3(-0.385, -0.005, 0.055), rHand: V3(-0.405, -0.09, 0.05),
      lEl: V3(0.31, 0.25, 0.08), lWr: V3(0.24, 0.08, 0.19), head: V3(0, 0.73, 0.135),
    };
    function limb(a, b, r0, r1, m, bulge = 0, at = 0.35, round = false) {
      const L = a.distanceTo(b), pts = [];
      const n = 26;
      for (let i = 0; i <= n; i++) {
        const t = i / n;
        let r = r0 + (r1 - r0) * t + bulge * Math.exp(-((t - at) ** 2) / 0.04);
        if (round) {
          const e = Math.min(0.08, (r0 * 0.9) / L);
          if (t < e) r *= Math.sqrt(Math.max(0.0001, 1 - ((e - t) / e) ** 2));
          if (t > 1 - e) r *= Math.sqrt(Math.max(0.0001, 1 - ((t - (1 - e)) / e) ** 2));
        }
        pts.push(new THREE.Vector2(Math.max(r, 0.002), t * L));
      }
      const geo = new THREE.LatheGeometry(pts, 40);
      const mesh = new THREE.Mesh(geo, m);
      mesh.castShadow = mesh.receiveShadow = true;
      mesh.position.copy(a);
      mesh.quaternion.setFromUnitVectors(V3(0, 1, 0), b.clone().sub(a).normalize());
      body.add(mesh);
      return mesh;
    }
    function ball(p, r, m, sx = 1, sy = 1, sz = 1) {
      const mesh = new THREE.Mesh(new THREE.SphereGeometry(r, 28, 18), m);
      mesh.position.copy(p); mesh.scale.set(sx, sy, sz); mesh.castShadow = mesh.receiveShadow = true; body.add(mesh); return mesh;
    }
    // legs (jeans)
    limb(J.lHip, J.lKnee, 0.078, 0.06, mat.denim, 0.006);
    limb(J.lKnee, J.lAnkle, 0.058, 0.046, mat.denim, 0.008, 0.3);
    limb(J.rHip, J.rKnee, 0.078, 0.06, mat.denim, 0.006);
    limb(J.rKnee, J.rMid, 0.058, 0.053, mat.denim, 0.006, 0.6);        // angulated shin (displaced fracture)
    limb(J.rMid, J.rAnkle, 0.055, 0.046, mat.denim, 0.004, 0.2);
    ball(J.rKnee, 0.061, mat.denim, 1, 1, 0.95); ball(J.lKnee, 0.062, mat.denim, 1, 1, 0.95);
    ball(J.rMid, 0.056, mat.denim, 1.05, 1, 1);
    // pelvis + belt
    const hips = new THREE.Mesh(new THREE.CapsuleGeometry(0.12, 0.1, 8, 24), mat.denim);
    hips.rotation.z = Math.PI / 2; hips.position.copy(J.pelvis).add(V3(0, 0.02, 0)); hips.scale.set(0.95, 1.1, 0.8); hips.castShadow = hips.receiveShadow = true; body.add(hips);
    const belt = new THREE.Mesh(new THREE.CapsuleGeometry(0.125, 0.11, 6, 24), mat.boot);
    belt.rotation.z = Math.PI / 2; belt.position.set(0, 0.1, 0.125); belt.scale.set(0.25, 1.12, 0.82); belt.castShadow = true; body.add(belt);
    const buckleM = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.035, 0.01), mat.metal); buckleM.position.set(0, 0.1, 0.228); body.add(buckleM);
    // torso (jacket)
    const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.16, 0.34, 10, 32), mat.jacket);
    torso.position.set(0, 0.32, 0.13); torso.scale.set(1.18, 1, 0.74); torso.castShadow = torso.receiveShadow = true; body.add(torso);
    const zip = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.5, 0.006), mat.metal); zip.position.set(0.03, 0.3, 0.25); zip.rotation.z = 0.04; body.add(zip);
    // arms
    limb(J.rSh, J.rEl, 0.058, 0.05, mat.jacket, 0.004); limb(J.rEl, J.rWr, 0.05, 0.04, mat.jacket, 0.006, 0.3);
    limb(J.lSh, J.lEl, 0.058, 0.05, mat.jacket, 0.004); limb(J.lEl, J.lWr, 0.05, 0.04, mat.jacket, 0.006, 0.3);
    ball(J.rEl, 0.05, mat.jacket); ball(J.lEl, 0.05, mat.jacket);
    // reflective tape on the sleeves
    function band(a, b2, at, r) {
      const d = b2.clone().sub(a), p2 = a.clone().add(d.clone().multiplyScalar(at));
      const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.03, 32, 1, true), mat.tape);
      m.position.copy(p2); m.quaternion.setFromUnitVectors(V3(0, 1, 0), d.normalize()); m.castShadow = true; body.add(m);
    }
    band(J.rEl, J.rWr, 0.72, 0.0442); band(J.lEl, J.lWr, 0.72, 0.0442); band(J.rSh, J.rEl, 0.55, 0.0578); band(J.lSh, J.lEl, 0.55, 0.0578);
    // a hand: palm, four slightly curled fingers with nails, thumb (palm down)
    function handAt(wrist, elbow, thumbSide) {
      const g = new THREE.Group();
      const dir = wrist.clone().sub(elbow).normalize();
      const xa = new THREE.Vector3().crossVectors(dir, V3(0, 0, 1)).normalize(), za = new THREE.Vector3().crossVectors(xa, dir).normalize();
      g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(xa, dir, za));
      g.position.copy(wrist);
      const add2 = (geo, m, px, py, pz, sx, sy, sz) => { const o = new THREE.Mesh(geo, m); o.position.set(px, py, pz); if (sx) o.scale.set(sx, sy, sz); o.castShadow = o.receiveShadow = true; g.add(o); return o; };
      add2(new THREE.SphereGeometry(1, 28, 18), mat.skin, 0, 0.012, -0.004, 0.032, 0.03, 0.022);          // wrist heel
      add2(new THREE.SphereGeometry(1, 28, 18), mat.skin, 0, 0.052, -0.002, 0.041, 0.05, 0.016);          // palm / back of the hand
      [0.044, 0.05, 0.047, 0.038].forEach((len, i) => {
        const fx = (i - 1.5) * 0.0168 * -thumbSide;
        const f = new THREE.Group(); f.position.set(fx, 0.094, -0.002); f.rotation.x = -0.32; f.rotation.z = (i - 1.5) * 0.06 * thumbSide; g.add(f);
        const seg = new THREE.Mesh(new THREE.CapsuleGeometry(0.0078 - i * 0.0004, len - 0.016, 6, 12), mat.skin); seg.position.y = len / 2; seg.castShadow = true; f.add(seg);
        const nail = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), mat.nail); nail.scale.set(0.0058, 0.0075, 0.0022); nail.position.set(0, len - 0.006, 0.0062); f.add(nail);
        const kn = new THREE.Mesh(new THREE.SphereGeometry(0.0085, 14, 10), mat.skin); kn.position.set(fx, 0.088, 0.004); kn.scale.set(1, 0.8, 0.6); g.add(kn);
      });
      const th = new THREE.Group(); th.position.set(thumbSide * 0.034, 0.026, -0.006); th.rotation.z = -thumbSide * 0.85; th.rotation.y = thumbSide * 0.4; g.add(th);
      const tseg = new THREE.Mesh(new THREE.CapsuleGeometry(0.0098, 0.03, 6, 12), mat.skin); tseg.position.y = 0.024; tseg.castShadow = true; th.add(tseg);
      body.add(g);
      return g;
    }
    handAt(J.rWr, J.rEl, 1); handAt(J.lWr, J.lEl, -1);
    // boots (toes up, turned out on the injured side)
    function bootAt(ankle, knee, outward) {
      const g = new THREE.Group();
      const shin = knee.clone().sub(ankle).normalize();
      // boot shaft round the lower shin + jeans hem over it
      const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.054, 0.15, 30), mat.boot);
      shaft.position.copy(shin.clone().multiplyScalar(0.045));
      shaft.quaternion.setFromUnitVectors(V3(0, 1, 0), shin);
      shaft.castShadow = shaft.receiveShadow = true; g.add(shaft);
      const hem = new THREE.Mesh(new THREE.CylinderGeometry(0.059, 0.061, 0.035, 30, 1), mat.denim);
      hem.position.copy(shin.clone().multiplyScalar(0.1));
      hem.quaternion.setFromUnitVectors(V3(0, 1, 0), shin);
      hem.castShadow = true; g.add(hem);
      // foot: toes up, tipped toward the feet end. Shaped from the boot's side profile (heel → toe cap →
      // instep → shaft), bevelled across its width; lugged sole, laces and eyelets
      const fd = V3(0, -Math.sin(0.55), Math.cos(0.55)), dorsal = V3(0, Math.cos(0.55), Math.sin(0.55));
      const lat = new THREE.Vector3().crossVectors(fd, dorsal);
      const basis = new THREE.Matrix4().makeBasis(fd, dorsal, lat);
      const prof = new THREE.Shape();
      prof.moveTo(-0.03, -0.035); prof.lineTo(0.19, -0.035);
      prof.quadraticCurveTo(0.248, -0.035, 0.25, 0.005); prof.quadraticCurveTo(0.25, 0.045, 0.2, 0.052);
      prof.quadraticCurveTo(0.13, 0.058, 0.07, 0.085); prof.lineTo(0.04, 0.115); prof.lineTo(-0.045, 0.118);
      prof.quadraticCurveTo(-0.062, 0.04, -0.03, -0.035);
      const fgeo = new THREE.ExtrudeGeometry(prof, { depth: 0.07, bevelEnabled: true, bevelThickness: 0.016, bevelSize: 0.013, bevelSegments: 5, curveSegments: 14 });
      fgeo.translate(0, -0.06, -0.035); fgeo.scale(0.92, 0.92, 0.92);
      { const uv = fgeo.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 7, uv.getY(i) * 7); }
      const foot = new THREE.Mesh(fgeo, mat.boot);
      foot.quaternion.setFromRotationMatrix(basis);
      foot.castShadow = foot.receiveShadow = true; g.add(foot);
      const sp = new THREE.Shape();
      sp.moveTo(-0.045, -0.06); sp.lineTo(0.2, -0.06); sp.quadraticCurveTo(0.268, -0.06, 0.266, -0.018); sp.lineTo(0.235, -0.022);
      sp.lineTo(-0.04, -0.022); sp.quadraticCurveTo(-0.062, -0.03, -0.045, -0.06);
      const sgeo = new THREE.ExtrudeGeometry(sp, { depth: 0.086, bevelEnabled: true, bevelThickness: 0.008, bevelSize: 0.006, bevelSegments: 3, curveSegments: 10 });
      sgeo.translate(0, -0.06, -0.043); sgeo.scale(0.92, 0.92, 0.92);
      const sole = new THREE.Mesh(sgeo, mat.sole);
      sole.quaternion.setFromRotationMatrix(basis);
      sole.castShadow = true; g.add(sole);
      // lugs across the sole
      for (let i = 0; i < 9; i++) {
        const lug = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.008, 0.094), mat.sole);
        const s0 = -0.03 + i * 0.03;
        lug.position.copy(fd.clone().multiplyScalar(s0 * 0.92)).add(dorsal.clone().multiplyScalar((-0.06 - 0.06 - 0.004) * 0.92));
        lug.quaternion.setFromRotationMatrix(basis);
        g.add(lug);
      }
      // laces + eyelets up the instep
      for (let i = 0; i < 5; i++) {
        const t = i / 4, ps = 0.17 - t * 0.12, pd = 0.016 + 0.045 * t;
        const lace = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.004, 0.06), mat.sole);
        lace.position.copy(fd.clone().multiplyScalar(ps * 0.92)).add(dorsal.clone().multiplyScalar(pd * 0.92));
        lace.quaternion.setFromRotationMatrix(basis); lace.rotateY(i % 2 ? 0.35 : -0.35);
        g.add(lace);
        for (const sg of [-1, 1]) {
          const ey = new THREE.Mesh(new THREE.TorusGeometry(0.0042, 0.0013, 6, 12), mat.metal);
          ey.position.copy(fd.clone().multiplyScalar(ps * 0.92)).add(dorsal.clone().multiplyScalar((pd - 0.002) * 0.92)).add(lat.clone().multiplyScalar(sg * 0.032));
          ey.quaternion.setFromRotationMatrix(basis); ey.rotateX(Math.PI / 2);
          g.add(ey);
        }
      }
      g.position.copy(ankle);
      g.rotation.z = outward;
      body.add(g);
      return g;
    }
    bootAt(J.rAnkle, J.rMid, -0.5); bootAt(J.lAnkle, J.lKnee, 0.25);
    // helmet
    const helmet = ball(J.head, 0.15, mat.helmet, 1, 1.12, 0.92);
    const visor = new THREE.Mesh(new THREE.SphereGeometry(0.153, 32, 16, -0.95, 1.9, 0.3, 1.0), mat.visor);
    visor.position.copy(J.head); visor.rotation.x = -Math.PI / 2; visor.scale.set(1, 1.12, 0.92); body.add(visor);
    void helmet;
    // ground contact darkening (ambient occlusion decal)
    (() => {
      const n = 512, c = cvs(n, n), x = c.getContext('2d');
      x.fillStyle = '#000'; x.fillRect(0, 0, n, n);
      const map = p => [(p.x + 1.1) / 2.2 * n, (1 - (p.y + 1.25) / 2.5) * n];
      x.filter = 'blur(10px)'; x.strokeStyle = '#fff'; x.lineCap = 'round';
      const seg = (a, b, w) => { const [x0, y0] = map(a), [x1, y1] = map(b); x.lineWidth = w; x.beginPath(); x.moveTo(x0, y0); x.lineTo(x1, y1); x.stroke(); };
      x.globalAlpha = 0.85;
      seg(J.rHip, J.rKnee, 30); seg(J.rKnee, J.rMid, 26); seg(J.rMid, J.rAnkle, 24); seg(J.lHip, J.lKnee, 30); seg(J.lKnee, J.lAnkle, 26);
      seg(V3(0, 0.05, 0), V3(0, 0.55, 0), 80); seg(J.rSh, J.rEl, 24); seg(J.rEl, J.rWr, 22); seg(J.head, J.head, 60);
      const decal = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 2.5), new THREE.MeshBasicMaterial({ color: 0x000000, alphaMap: new THREE.CanvasTexture(c), transparent: true, opacity: 0.55, depthWrite: false }));
      decal.position.set(0, 0, 0.0018);
      body.add(decal); // hides with the patient (HUD previews)
    })();

    // ── camera rig
    const rig = { focus: V3(0, 0, 0), up: V3(0, 1, 0), height: 1.2, mode: 'top', dirty: true };
    function place() {
      const W = window.innerWidth, H = window.innerHeight;
      if (cv.width !== W || cv.height !== H) { R.setSize(W, H, false); cam.aspect = W / H; cam.updateProjectionMatrix(); }
      if (rig.mode === 'third') {
        cam.up.set(0, 0, 1);
        cam.position.set(1.15, -2.45, 1.45);
        cam.lookAt(-0.05, -0.2, 0.1);
      } else {
        cam.up.copy(rig.up);
        cam.position.copy(rig.focus).add(V3(0, 0, rig.height));
        cam.lookAt(rig.focus);
      }
      cam.updateMatrixWorld();
      sun.target.position.copy(rig.mode === 'third' ? V3(0, -0.2, 0) : rig.focus);
      sun.position.copy(sun.target.position).add(V3(-1.6, 1.5, 3.4));
    }
    function project(p) {
      const q = p.clone().project(cam);
      return { x: (q.x + 1) / 2, y: (1 - q.y) / 2, visible: q.z < 1 && q.z > -1 };
    }
    let limbSel = 'leg';
    const api = {
      view(kind) {
        limbSel = kind;
        rig.mode = kind === 'third' ? 'third' : 'top';
        if (kind === 'arm') {
          const a = J.rEl, b = J.rWr;
          rig.focus = a.clone().add(b).multiplyScalar(0.5);
          rig.up = V3(a.x - b.x, a.y - b.y, 0).normalize();
          rig.height = a.distanceTo(b) / (0.38 * 2 * Math.tan(25 * Math.PI / 180));
        } else if (kind === 'leg') {
          const a = J.rKnee, b = J.rAnkle;
          rig.focus = a.clone().add(b).multiplyScalar(0.5);
          rig.up = V3(a.x - b.x, a.y - b.y, 0).normalize();
          rig.height = a.distanceTo(b) / (0.38 * 2 * Math.tan(25 * Math.PI / 180));
        }
        rig.dirty = true;
      },
      joints(arm) {
        return arm ? { segLen: J.rEl.distanceTo(J.rWr) } : { segLen: J.rKnee.distanceTo(J.rAnkle) };
      },
      tick() {
        if (!rig.dirty && cv.width === window.innerWidth && cv.height === window.innerHeight) return false;
        rig.dirty = false;
        place();
        R.render(scene, cam);
        if (limbSel === 'arm') {
          app.anc = { prox: project(J.rEl), dist: project(J.rWr), cms: project(J.rHand.clone().add(V3(0, -0.03, 0.03))), core: project(J.chest) };
        } else if (limbSel === 'leg') {
          app.anc = { prox: project(J.rKnee), dist: project(J.rAnkle), cms: project(J.rAnkle.clone().add(V3(-0.07, -0.08, 0.16))), core: project(J.chest) };
        }
        return true;
      },
      rotate(dx) { rig.up.applyAxisAngle(V3(0, 0, 1), dx); rig.dirty = true; },
      hide() { cv.style.display = 'none'; },
      body(v) { body.visible = v !== false; rig.dirty = true; },
      zoom(k) { rig.height = clamp(rig.height * k, 0.55, 3.2); rig.dirty = true; },
    };
    // right-drag turns the view, wheel zooms (what NZA.Cam does in game)
    let drag = null;
    window.addEventListener('mousedown', e => { if (e.button === 2) drag = { x: e.clientX }; });
    window.addEventListener('mousemove', e => { if (drag) { api.rotate(-(e.clientX - drag.x) / window.innerWidth * Math.PI); drag.x = e.clientX; } });
    window.addEventListener('mouseup', e => { if (e.button === 2) drag = null; });
    window.addEventListener('wheel', e => { if (app.S) api.zoom(e.deltaY > 0 ? 1.08 : 0.93); });
    window.addEventListener('resize', () => { rig.dirty = true; });
    app.previewTick = () => { api.tick(); };
    app._world = api;
    api.tick();
    return api;
  }

  NZA.app(APP, A);
})();
