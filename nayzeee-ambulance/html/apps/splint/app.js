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
   Also hosts the mobility card (wheelchair / pushing / crutches) in 'hud' mode.

   Lua → JS   open { mode = 'proc', locale, region, regionLabel, device, deviceLabel, deviceModel,
                     limb, segment, joints { prox, dist, cms }, fracture { kind, kindLabel, bone,
                     boneLabel, displaced, angle }, open, dressed, severity, pulse, pulseWhy, hr,
                     sys, refill, responsive, name, sex, pain, size { width, depth, wall,
                     limbRadius }, segLen, fov, upright, tune, keys }
              open { mode = 'hud', locale, hud }     hud (data)    hudOff    result (outcome)
              anchors { prox, dist, cms, core }
   JS → Lua   splint:finish (result) · splint:abort · splint:done · splint:close
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

  // closed-cell foam: tiny dimples
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
  // nylon webbing: ribs along the strap + stitched edge lines
  function webbingTextures() {
    const w = 64, h = 256;
    const c = cvs(w, h), cc = c.getContext('2d');
    cc.fillStyle = '#1c1f22'; cc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { cc.fillStyle = x % 4 ? 'rgba(255,255,255,.035)' : 'rgba(0,0,0,.25)'; cc.fillRect(x, 0, 1, h); }
    for (let y = 0; y < h; y += 3) { cc.fillStyle = 'rgba(255,255,255,.025)'; cc.fillRect(0, y, w, 1); }
    // edge binding + stitch lines (generic, no branding)
    cc.fillStyle = '#121416'; cc.fillRect(0, 0, 4, h); cc.fillRect(w - 4, 0, 4, h);
    cc.fillStyle = 'rgba(15,180,168,.85)';
    for (let y = 0; y < h; y += 8) { cc.fillRect(6, y, 2, 5); cc.fillRect(w - 8, y, 2, 5); }
    const hh = cvs(w, h), hc = hh.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 2) { hc.fillStyle = x % 4 ? '#a0a0a0' : '#606060'; hc.fillRect(x, 0, 1, h); }
    hc.fillStyle = '#b8b8b8'; hc.fillRect(0, 0, 3, h); hc.fillRect(w - 3, 0, 3, h);
    return { map: tex(c, [1, 4], true), normal: tex(normalFromHeight(hh, 3), [1, 4]) };
  }
  // brushed / moulded shell grain
  function shellTextures() {
    const n = 256, r = rng(7);
    const h = cvs(n, n), hc = h.getContext('2d');
    hc.fillStyle = '#808080'; hc.fillRect(0, 0, n, n);
    for (let i = 0; i < 5000; i++) { hc.fillStyle = `rgba(${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},${r() > 0.5 ? 255 : 0},.06)`; hc.fillRect(r() * n, r() * n, 1 + r() * 2, 1); }
    return { normal: tex(normalFromHeight(h, 0.6), [4, 4]) };
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

    // ── fade where the splint passes under the limb (screen-space capsule) ──
    const FU = { uLimbA: { value: new THREE.Vector2() }, uLimbB: { value: new THREE.Vector2() }, uLimbR: { value: 0 }, uFade: { value: 0 }, uOpacity: { value: 1 } };
    const fadeMat = (mat, keyName, floor = 0.1) => {
      mat.transparent = true;
      mat.onBeforeCompile = sh => {
        Object.assign(sh.uniforms, FU);
        sh.fragmentShader = sh.fragmentShader
          .replace('#include <common>', `#include <common>
uniform vec2 uLimbA; uniform vec2 uLimbB; uniform float uLimbR; uniform float uFade; uniform float uOpacity;
float nzaSeg(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0); return length(pa - ba * h); }`)
          .replace('#include <dithering_fragment>', `#include <dithering_fragment>
{ float dd = nzaSeg(gl_FragCoord.xy, uLimbA, uLimbB); float kk = (1.0 - smoothstep(uLimbR * 0.8, uLimbR * 1.04, dd)) * uFade;
  gl_FragColor.a *= uOpacity * (1.0 - kk * ${(1 - floor).toFixed(3)}); }`);
      };
      mat.customProgramCacheKey = () => `nzafade-${keyName}`;
      return mat;
    };
    const foamT = foamTextures(), webT = webbingTextures(), shellT = shellTextures();
    const M = {
      foam: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#3c444b'), map: foamT.map, normalMap: foamT.normal, normalScale: new THREE.Vector2(0.7, 0.7), roughness: 0.94, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.55 }), 'foam', 0.12),
      shell: fadeMat(new THREE.MeshPhysicalMaterial({ color: lin('#0c9a8e'), normalMap: shellT.normal, normalScale: new THREE.Vector2(0.25, 0.25), roughness: 0.36, metalness: 0, clearcoat: 0.75, clearcoatRoughness: 0.2, side: THREE.DoubleSide, envMapIntensity: 1.1 }), 'shell', 0.06),
      cap: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#0a7f76'), roughness: 0.5, side: THREE.DoubleSide }), 'cap', 0.06),
      pad: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#e6ecee'), normalMap: foamT.normal, normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.97, envMapIntensity: 0.6 }), 'pad', 0.35),
      roll: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#59666c'), normalMap: foamT.normal, roughness: 0.92 }), 'roll', 0.2),
      plateFoam: fadeMat(new THREE.MeshStandardMaterial({ color: lin('#3c444b'), map: foamT.map, normalMap: foamT.normal, roughness: 0.95 }), 'pfoam', 0.2),
      strap: new THREE.MeshStandardMaterial({ map: webT.map, normalMap: webT.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.68, metalness: 0, side: THREE.DoubleSide, envMapIntensity: 0.7 }),
      metal: new THREE.MeshStandardMaterial({ color: lin('#9aa3a9'), metalness: 0.95, roughness: 0.28, envMapIntensity: 1.3 }),
      tab: new THREE.MeshPhysicalMaterial({ color: lin('#0b8379'), roughness: 0.42, clearcoat: 0.6, clearcoatRoughness: 0.25 }),
      dark: new THREE.MeshStandardMaterial({ color: lin('#16191c'), roughness: 0.55, metalness: 0.2 }),
      glow: new THREE.MeshBasicMaterial({ color: lin('#2fe0d0'), transparent: true, opacity: 0.0, depthWrite: false }),
    };
    const group = new THREE.Group();
    scene.add(group);
    let G = null;
    let dirty = true;

    const NX = 96, K = 24, RC = 6;
    const RING = (K + 1) + RC + (K + 1) + RC;

    function disposeGroup() {
      group.traverse(o => { if (o.geometry) o.geometry.dispose(); });
      while (group.children.length) group.remove(group.children[0]);
    }

    // cross-section of the trough at local x for the current shaping state
    function profile(x) {
      const o = G.o, P = G.P;
      const t = (x + o.L / 2) / o.L;
      let shaped = 0, over = 0;
      for (const p of P.points) {
        const g = Math.exp(-((x - p.x) * (x - p.x)) / (2 * o.sig * o.sig));
        shaped = Math.max(shaped, Math.min(1, p.f / P.zone0) * g);
        if (p.f > P.zone1) over = Math.max(over, Math.min(1, (p.f - P.zone1) * 30) * g);
      }
      const z0 = -(o.limbR + 0.003);
      let hw = o.limbR + 0.003 + o.gap * (1 - shaped) - 0.004 * over;
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
      const pos = new Float32Array((NX + 1) * RING * 3), uv = new Float32Array((NX + 1) * RING * 2);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      const foam = [], shell = [];
      for (let i = 0; i < NX; i++) {
        for (let j = 0; j < RING; j++) {
          const j2 = (j + 1) % RING;
          const a = i * RING + j, b = i * RING + j2, c = (i + 1) * RING + j, d = (i + 1) * RING + j2;
          (j < K ? foam : shell).push(a, d, b, a, c, d);
        }
      }
      geo.setIndex(foam.concat(shell));
      geo.addGroup(0, foam.length, 0);
      geo.addGroup(foam.length, shell.length, 1);
      const mesh = new THREE.Mesh(geo, [M.foam, M.shell]);
      mesh.renderOrder = 2;
      group.add(mesh);
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
      G.trough = mesh; G.caps = caps;
      G.ringBuf = new Float32Array(RING * 2);
      fillTrough(true);
    }

    function fillTrough(first) {
      const o = G.o;
      const pos = G.trough.geometry.attributes.position.array, uv = G.trough.geometry.attributes.uv.array;
      const cap = G.caps.geometry.attributes.position.array;
      for (let i = 0; i <= NX; i++) {
        const x = -o.L / 2 + o.L * i / NX;
        ringPoints(x, G.ringBuf);
        for (let j = 0; j < RING; j++) {
          const p = (i * RING + j) * 3, q = (i * RING + j) * 2;
          pos[p] = x; pos[p + 1] = G.ringBuf[j * 2]; pos[p + 2] = G.ringBuf[j * 2 + 1];
          if (first) { uv[q] = j / RING * 3; uv[q + 1] = (x + o.L / 2) * 6; }
          if (i === 0 || i === NX) {
            const e = i === 0 ? 0 : 1, cp = (e * RING + j) * 3;
            cap[cp] = x; cap[cp + 1] = pos[p + 1]; cap[cp + 2] = pos[p + 2];
          }
        }
      }
      G.trough.geometry.attributes.position.needsUpdate = true;
      if (first) G.trough.geometry.attributes.uv.needsUpdate = true;
      G.trough.geometry.computeVertexNormals();
      G.trough.geometry.computeBoundingSphere();
      G.caps.geometry.attributes.position.needsUpdate = true;
      G.caps.geometry.computeVertexNormals();
      G.caps.geometry.computeBoundingSphere();
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
        // heel strap slot ribs on the plate top edge
        for (const sgn of [-1, 1]) {
          const rib = new THREE.Mesh(new THREE.BoxGeometry(0.018, 0.022, 0.008), M.tab);
          rib.position.set(o.L / 2 + 0.002, sgn * (w / 2 - 0.02), base + hgt - 0.004);
          group.add(rib);
        }
      }
      if (o.kind === 'arm') {
        const hw = profile(o.L / 2 - 0.04).hw;
        const roll = new THREE.Mesh(new THREE.CylinderGeometry(0.019, 0.019, hw * 2 + 0.004, 24, 1), M.roll);
        roll.position.set(o.L / 2 - 0.045, 0, z0 + 0.019);
        roll.renderOrder = 3;
        group.add(roll);
      }
    }

    function buildPads() {
      const o = G.o;
      G.pads = o.sites.map(site => {
        const pair = new THREE.Group();
        for (const sgn of [-1, 1]) {
          const g = new THREE.CapsuleGeometry(0.011, 0.034, 6, 14);
          g.rotateZ(Math.PI / 2);
          const m = new THREE.Mesh(g, M.pad);
          m.scale.set(1, 0.9, 1.35);
          m.position.set(0, sgn * (o.limbR + 0.011), -(o.limbR + 0.003) + 0.024);
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
      G.straps = o.strapX.map(x => {
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
        // anchor tab on the near rim, cam buckle on the far rim
        const tab = new THREE.Group();
        const tb = new THREE.Mesh(new THREE.BoxGeometry(o.strapW + 0.012, 0.012, 0.016), M.tab);
        tab.add(tb);
        const rivet = new THREE.Mesh(new THREE.CylinderGeometry(0.0035, 0.0035, 0.004, 12), M.metal);
        rivet.rotation.x = Math.PI / 2; rivet.position.set(0, 0, 0.009);
        tab.add(rivet);
        group.add(tab);
        const buckle = new THREE.Group();
        const bb = new THREE.Mesh(new THREE.BoxGeometry(o.strapW + 0.01, 0.016, 0.012), M.metal);
        buckle.add(bb);
        const lever = new THREE.Mesh(new THREE.BoxGeometry(o.strapW * 0.62, 0.012, 0.006), M.tab);
        lever.position.set(0, 0.002, 0.008);
        buckle.add(lever);
        buckle.visible = false;
        group.add(buckle);
        return { x, mesh, tab, buckle, key: '' };
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
        const oy = yA + side * (0.012 + u * 0.19), oz = ground + (pr.zr - ground) * Math.exp(-u * 26) + 0.0015;
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
      s.tab.position.set(s.x, info.yA - o.anchorSide * 0.002, info.zr - 0.004);
      s.buckle.position.set(s.x, -info.yA, info.zr + 0.002);
      s.buckle.visible = st.k >= 0.999;
    }

    const api = {
      ok: true,
      // o = { kind, segment, L, width, depth, th, limbR, plate, sites:[{x}], strapX:[x], strapW, anchorSide, sig }
      build(o) {
        disposeGroup();
        const gap = Math.max(0.008, o.width / 2 - o.th - o.limbR - 0.003);
        G = { o: Object.assign({ gap, flare: 0.34, sig: 0.04 }, o), P: { points: [], zone0: 0.72, zone1: 1.0 } };
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
        group.visible = !!st.visible;
        if (!st.visible) { dirty = true; return; }
        group.position.set(st.C.x, -st.C.y, 0);
        group.rotation.set(0, 0, Math.atan2(-st.s.y, st.s.x));
        group.scale.setScalar(st.ppm);
        FU.uLimbA.value.set(st.limbA.x, st.H - st.limbA.y);
        FU.uLimbB.value.set(st.limbB.x, st.H - st.limbB.y);
        FU.uLimbR.value = st.limbR;
        FU.uFade.value = st.fade;
        FU.uOpacity.value = st.opacity;
        // shaping
        const P = G.P;
        P.points = st.points || [];
        P.zone0 = st.zone[0]; P.zone1 = st.zone[1];
        const sk = P.points.map(p => p.f.toFixed(3)).join(',');
        if (sk !== G.shapeKey) { G.shapeKey = sk; fillTrough(false); G.strapsStale = true; }
        // pads
        (G.pads || []).forEach((pair, i) => {
          const p = st.pads && st.pads[i];
          pair.visible = !!(p && p.on);
          if (pair.visible) { const k = 1 + (p.pop || 0) * 0.35; pair.scale.set(k, k, k); }
        });
        // straps
        (G.straps || []).forEach((s, i) => {
          const ss = st.straps && st.straps[i] ? st.straps[i] : { k: 0, tension: 0, show: false };
          s.mesh.visible = s.tab.visible = ss.show !== false;
          if (!s.mesh.visible) { s.buckle.visible = false; return; }
          const kk = `${ss.k.toFixed(3)}|${(ss.tension || 0).toFixed(3)}`;
          if (kk !== s.key || G.strapsStale) { s.key = kk; fillStrap(s, ss); }
        });
        G.strapsStale = false;
        dirty = true;
      },
      render(W, H, fov) {
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
      clear() { R.clear(); dirty = true; },
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
      this.pp.el.classList.add('sp-pp');
      this.enterStep(1);
      if (d.open) setTimeout(() => this.pp && this.S === S && this.pp.flash('warn', d.dressed ? T('open_dressed', 'Open fracture, already covered. Keep the dressing clean under the splint.') : T('open_warn', 'Open fracture: the bone broke the skin. Cover it before you strap over it.'), 5200), 600);
      else if (d.fracture && d.fracture.displaced) setTimeout(() => this.pp && this.S === S && this.pp.flash('warn', T('displaced', 'Displaced %s°. Splint it where it lies - it is set in hospital.', Math.round(d.fracture.angle || 0)), 4600), 600);
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
        if (id === tool) return S && id === 'cms' && S.cms.state === 'ready' ? 'active need' : 'active';
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
        title = allLocked ? T('s3_title_cms', 'Check below the splint') : T('s3_title', 'Strap it in place');
        text = allLocked
          ? T('s3_text_cms', 'Click the **%s** to check circulation, movement and feeling below the splint.', cmsName)
          : T('s3_text', 'Click a strap to wrap it over the limb, then click again (or {%s}) when the needle sits **in the band**. Keep straps off the break.', keyLabel(this.K.set));
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
    initialPose(f) {
      const side = this.bodySide(f);
      return { cu: 0.04, cv: side * (this.size.width * 1.45 + 0.03), phi: side * 0.32 };
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
    overUi(e) { return !!(e.target && e.target.closest && e.target.closest('.pp-card,.pp-read,.pp-belt,.pp-bot,.sp-res,.sp-hud,.sp-frac,.sp-cms')); },

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
    padY() { return this.size.limbRadius + 0.011; },
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
          <div class="who"><div class="ttl">${esc(this.d.regionLabel || '')}</div><div class="dev">${esc(this.d.deviceLabel || '')} · ${esc(this.d.deviceModel || '')}</div>
            <div class="chips"><span class="chipx sm teal">${icon('check')}${esc(T('res_cms', 'Distal check intact'))}</span>${r.pressure ? `<span class="chipx sm amber">${esc(T('res_press', '%s pressure point(s)', r.pressure))}</span>` : ''}${S.cms.fixed ? `<span class="chipx sm">${esc(T('res_fixed', 'Strap re-done'))}</span>` : ''}</div></div>
        </div>
        <div class="bars">${row(T('res_align', 'Alignment'), r.align ?? score, 'ruler')}${row(T('res_mould', 'Shaping'), r.mould ?? score, 'hand')}${row(T('res_straps', 'Straps'), r.straps ?? score, 'cuff')}</div>
        ${o.msg ? `<div class="msg">${esc(o.msg)}</div>` : ''}`;
      this.resEl.hidden = false;
      this.cmsEl.hidden = true;
      if (this.trace) { this.trace.stop(); this.trace = null; }
      this.pp.complete({
        title: T('done_title', 'Splint secured'),
        text: T('done_text', 'The limb is held above and below the break. Re-check the pulse below it on the way in.'),
        label: T('done', 'Done'), onDone: () => this.done(),
      });
      this.pp.set({ wide: { label: T('score', 'Score'), value: score, tone: 'teal', meter: { value: score / 100 }, caption: T('grade', 'Grade %s', grade), captionTone: 'teal' }, stats: [] });
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
      uc.setTransform(1, 0, 0, 1, 0, 0); uc.clearRect(0, 0, fu.w, fu.h);
      c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, w, h);
      const S = this.S;
      const f = this.frame();
      const U = h / 1080;
      this.U = U;
      const tags = {};
      if (!f) { this.syncTags(tags); if (this.gl) { this.gl.update({ visible: false }); this.gl.clear(); } return; }
      const g = this.geom(f, S.pose);
      const introK = easeOut((now - (S.intro || now)) / 420);

      // 3D splint
      if (this.gl) {
        if (!this.glBuilt) {
          this.gl.build({
            kind: this.kind, segment: this.segment, L: this.Ls, width: this.size.width, depth: this.size.depth, th: this.size.wall,
            limbR: this.size.limbRadius, plate: this.kind === 'leg' && this.segment === 'lower', strapW: STRAP_W[this.kind],
            sites: S.sites.map(s => ({ x: s.x })), strapX: S.straps.map(s => s.x), anchorSide: -S.side,
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
      this.drawShadow(f, g, introK);
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
          const gh = Math.max(74 * U, 0.12 * g.ppm), gw = 10 * U;
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
          t.el.innerHTML = `<span class="lbl ${tone}">${/\bok\b/.test(tone) && !/mono/.test(tone) ? icon('check') : ''}<span class="tx">${esc(o.label)}${o.sub ? `<small>${esc(o.sub)}</small>` : ''}</span></span>`;
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

    /* ═════════════════════ MOBILITY CARD ═════════════════════ */
    hudShow(h) {
      this.hud = Object.assign({}, this.hud && this.hud.kind === h.kind ? this.hud : {}, h);
      const o = this.hud;
      const el = this.hudEl;
      const kind = o.kind || 'chair';
      const speed = Number(o.speed) || 0;
      const max = Math.max(0.1, Number(o.max) || 2);
      const frac = clamp(Math.abs(speed) / max, 0, 1.4);
      const slope = Number(o.slope) || 0;
      const keys = (o.keys || []).map(k => `<span class="hk">${(k.keys || []).map(x => `<kbd>${esc(x)}</kbd>`).join('')}<em>${esc(k.label)}</em></span>`).join('');
      el.className = `sp-hud nza-hud solid kind-${kind} ${o.state ? `st-${o.state}` : ''}${this.S ? ' away' : ''}`;
      if (kind === 'crutch') {
        el.innerHTML = `
          <div class="hrow"><span class="hic">${icon('crutch')}</span><div class="tx"><span class="kick">${esc(T('hud_kicker_mob', 'Mobility aid'))}</span><b>${esc(o.title || '')}</b><small>${esc(o.sub || '')}</small></div></div>
          ${keys ? `<div class="keys">${keys}</div>` : ''}`;
      } else {
        const R = 30, A0 = 150, SW = 240;
        const pt = (fv, r = R) => { const a = (A0 + SW * clamp(fv, 0, 1)) * Math.PI / 180; return [40 + r * Math.cos(a), 40 + r * Math.sin(a)]; };
        const arc = (f0, f1) => { const [x0, y0] = pt(f0), [x1, y1] = pt(f1); return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${R} ${R} 0 ${(f1 - f0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`; };
        const fv = clamp(frac, 0, 1);
        const kmh = Math.abs(speed) * 3.6;
        const steep = Math.abs(slope) >= 8;
        el.innerHTML = `
          <div class="hrow">
            <div class="spd ${speed < -0.05 ? 'rev' : ''}"><svg viewBox="0 0 80 74"><path class="trk" d="${arc(0, 1)}"/>${fv > 0.005 ? `<path class="fill" d="${arc(0, Math.max(0.01, fv))}"/>` : ''}</svg><b>${kmh.toFixed(1)}</b><i>${esc(T('kmh', 'km/h'))}</i>${speed < -0.05 ? `<span class="rv">${esc(T('rev', 'REV'))}</span>` : ''}</div>
            <div class="tx"><span class="kick">${icon(kind === 'push' ? 'hand' : 'wheelchair')}${esc(kind === 'push' ? T('hud_kicker_push', 'Pushing') : T('hud_kicker_chair', 'Wheelchair'))}</span><b>${esc(o.title || '')}</b><small>${esc(o.sub || '')}</small>
              <div class="slope ${steep ? 'steep' : ''}"><span class="gl"><i style="transform:rotate(${clamp(-slope, -30, 30).toFixed(1)}deg)"></i></span><span>${slope > 0.5 ? '▲' : slope < -0.5 ? '▼' : '='} ${Math.abs(slope).toFixed(0)}°</span><em>${esc(steep ? T('steep', 'Steep') : T('grade_lbl', 'Grade'))}</em></div>
            </div>
          </div>
          ${o.blocked ? `<div class="blk">${icon('alert')}<span>${esc(o.blocked)}</span></div>` : ''}
          ${keys ? `<div class="keys">${keys}</div>` : ''}`;
      }
      el.hidden = false;
    },
    hudHide() {
      this.hud = null;
      this.hudEl.hidden = true;
    },

    /* ═════════════════════ PREVIEW ═════════════════════ */
    preview(stage) {
      stage = stage || new URLSearchParams(location.search).get('stage') || 'place';
      LOC = {};
      const W = previewWorld(this);
      const arm = stage === 'arm' || stage.startsWith('arm-');
      NZA.mock(`${APP}:finish`, r => ({ ok: true, outcome: { score: r.score, grade: r.score >= 90 ? 'S' : r.score >= 80 ? 'A' : r.score >= 68 ? 'B' : 'C', msg: arm ? 'Right forearm splinted · pain easing' : 'Right lower leg splinted · pain easing' } }));
      if (stage.startsWith('hud')) {
        this.procStop();
        if (W) { W.view('third'); W.tick(); }
        const hudDemo = {
          'hud-chair': { kind: 'chair', title: 'Wheelchair', sub: 'Rolling', state: 'drive', speed: 1.42, max: 1.9, slope: -4, keys: [{ keys: ['W', 'S'], label: 'Drive' }, { keys: ['A', 'D'], label: 'Turn' }, { keys: ['F'], label: 'Stand up' }] },
          'hud-blocked': { kind: 'chair', title: 'Wheelchair', sub: 'Blocked', state: 'blocked', blocked: 'Curb too high', speed: 0, max: 1.9, slope: 2, keys: [{ keys: ['W', 'S'], label: 'Drive' }, { keys: ['A', 'D'], label: 'Turn' }, { keys: ['F'], label: 'Stand up' }] },
          'hud-push': { kind: 'push', title: 'Pushing a wheelchair', sub: 'Michael Garcia', state: 'push', speed: 1.1, max: 1.9, slope: 6, keys: [{ keys: ['G'], label: 'Let go' }] },
          'hud-crutch': { kind: 'crutch', title: 'On crutches', sub: 'Walking · no running', keys: [{ keys: ['/crutches'], label: 'Put away' }] },
        }[stage] || {};
        NZA.demo(APP, { mode: 'hud', hud: hudDemo });
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
      const S = this.S;
      const at = (fn, ms) => setTimeout(() => { if (this.S === S) fn(); }, ms);
      const st = stage.replace(/^arm-?/, '') || 'place';
      const later = ['aligned', 'pad', 'shape', 'strap', 'cms', 'cmsbad', 'done'];
      if (later.includes(st)) {
        at(() => {
          S.moved = true;
          if (st === 'aligned') { S.pose = { cu: 0.006, cv: 0.004, phi: 0.02 }; S.alignHold = -99; return; }
          S.pose = { cu: 0.004, cv: 0.003, phi: 0.012 };
          this.update(performance.now(), 0);
          this.lockSplint();
        }, 160);
      }
      if (st === 'pad') {
        at(() => { S.sites[0].padded = true; S.sites[0].pop = 0; this.refreshTools(); this.updateReadout(true); }, 1000);
      }
      if (st === 'shape') {
        at(() => {
          S.sites.forEach(s => { s.padded = true; });
          S.tool = 'shape'; this.enterStep(2, true);
          S.points.forEach((p, i) => { if (i < 2) { p.f = i ? 0.9 : 0.84; p.done = true; } });
          S.points[2].f = 0.58; S.press = 2;
          this._holdPreview = true;
          this.updateReadout(true);
        }, 1000);
      }
      if (['strap', 'cms', 'cmsbad', 'done'].includes(st)) {
        at(() => {
          S.sites.forEach(s => { s.padded = true; });
          S.points.forEach(p => { p.f = 0.86; p.done = true; });
          this.checkShapeDone();
        }, 1000);
      }
      if (st === 'strap') {
        at(() => {
          const s0 = S.straps[0]; s0.state = 'locked'; s0.k = 1; s0.tension = 0.68; s0.quality = 96;
          const s1 = S.straps[1]; s1.state = 'sweep'; s1.k = 1; s1.ph = 0.21; S.sweeping = 1;
          this.refreshTools(); this.updateReadout(true);
        }, 1950);
      }
      if (st === 'cms' || st === 'cmsbad' || st === 'done') {
        at(() => {
          S.straps.forEach((s, i) => { s.state = 'locked'; s.k = 1; s.tension = st === 'cmsbad' && i === 1 ? 0.93 : 0.66; s.quality = s.tension > 0.9 ? 30 : 94; s.tight = s.tension > 0.9; if (s.tight) S.tightEver += 1; });
          S.cms.state = 'ready'; S.tool = 'cms';
          this.enterStep(3, true); this.refreshTools();
        }, 1950);
        if (st !== 'cms') at(() => this.cmsCheck(), 2150);
      }
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
      [0.02, 0.52].forEach(f => {
        const sx = w * f;
        x.fillStyle = 'rgba(12,20,38,.5)'; x.fillRect(sx, 0, 3, hgt);
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
      for (let i = 0; i < 5200; i++) { x.fillStyle = `rgba(0,0,0,${0.15 + r() * 0.6})`; x.beginPath(); x.arc(r() * w, r() * hgt, 0.5 + r() * 2.2, 0, Math.PI * 2); x.fill(); }
      return tex(c, [1, 4], true);
    }

    const tA = asphalt(), tD = denim(), tJ = leather('#4a2a22', 31), tB = leather('#17181a', 47), tG = leather('#1e1f22', 63);
    const mat = {
      ground: new THREE.MeshStandardMaterial({ map: tA.map, normalMap: tA.normal, normalScale: new THREE.Vector2(0.9, 0.9), roughness: 0.94, metalness: 0 }),
      paint: new THREE.MeshStandardMaterial({ map: paint(), transparent: true, roughness: 0.7, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }),
      curb: new THREE.MeshStandardMaterial({ color: lin('#8d8c86'), roughness: 0.9, normalMap: tA.normal, normalScale: new THREE.Vector2(0.4, 0.4) }),
      denim: new THREE.MeshStandardMaterial({ map: tD.map, normalMap: tD.normal, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 0.92 }),
      jacket: new THREE.MeshStandardMaterial({ map: tJ.map, normalMap: tJ.normal, normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.55, metalness: 0.05 }),
      boot: new THREE.MeshStandardMaterial({ map: tB.map, normalMap: tB.normal, roughness: 0.5, metalness: 0.05 }),
      sole: new THREE.MeshStandardMaterial({ color: lin('#2a2826'), roughness: 0.85 }),
      glove: new THREE.MeshStandardMaterial({ map: tG.map, normalMap: tG.normal, roughness: 0.6 }),
      helmet: new THREE.MeshPhysicalMaterial({ color: lin('#1c1e21'), roughness: 0.45, clearcoat: 0.6, clearcoatRoughness: 0.35 }),
      visor: new THREE.MeshPhysicalMaterial({ color: lin('#121820'), roughness: 0.05, metalness: 0.2, clearcoat: 1, transparent: true, opacity: 0.92 }),
      metal: new THREE.MeshStandardMaterial({ color: lin('#a8adb2'), metalness: 0.95, roughness: 0.3 }),
      skin: new THREE.MeshStandardMaterial({ color: lin('#b98365'), roughness: 0.65 }),
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
    function limb(a, b, r0, r1, m, bulge = 0, at = 0.35) {
      const L = a.distanceTo(b), pts = [];
      const n = 26;
      for (let i = 0; i <= n; i++) {
        const t = i / n;
        let r = r0 + (r1 - r0) * t + bulge * Math.exp(-((t - at) ** 2) / 0.04);
        const e = Math.min(0.08, (r0 * 0.9) / L);
        if (t < e) r *= Math.sqrt(Math.max(0.0001, 1 - ((e - t) / e) ** 2));
        if (t > 1 - e) r *= Math.sqrt(Math.max(0.0001, 1 - ((t - (1 - e)) / e) ** 2));
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
    ball(J.rHand.clone().add(V3(0, 0.03, 0)), 0.048, mat.glove, 0.85, 1.35, 0.6);
    ball(J.lWr.clone().add(V3(-0.03, -0.05, 0.02)), 0.048, mat.glove, 0.85, 1.3, 0.6);
    // boots (toes up, turned out on the injured side)
    function bootAt(ankle, knee, outward) {
      const g = new THREE.Group();
      const shin = knee.clone().sub(ankle).normalize();
      // boot shaft round the lower shin + jeans hem over it
      const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.054, 0.15, 30), mat.boot);
      shaft.position.copy(shin.clone().multiplyScalar(0.045));
      shaft.quaternion.setFromUnitVectors(V3(0, 1, 0), shin);
      shaft.castShadow = shaft.receiveShadow = true; g.add(shaft);
      const hem = new THREE.Mesh(new THREE.TorusGeometry(0.054, 0.009, 10, 30), mat.denim);
      hem.position.copy(shin.clone().multiplyScalar(0.105));
      hem.quaternion.setFromUnitVectors(V3(0, 0, 1), shin);
      hem.castShadow = true; g.add(hem);
      // foot: toes up, tipped toward the feet end; sole on the plantar side
      const fd = V3(0, -Math.sin(0.55), Math.cos(0.55));
      const plantar = V3(0, -Math.cos(0.55), -Math.sin(0.55));
      const foot = new THREE.Mesh(new THREE.CapsuleGeometry(0.046, 0.15, 8, 22), mat.boot);
      foot.quaternion.setFromUnitVectors(V3(0, 1, 0), fd);
      foot.position.copy(fd.clone().multiplyScalar(0.085)).add(plantar.clone().multiplyScalar(0.012));
      foot.scale.set(1.08, 1, 0.92);
      foot.castShadow = foot.receiveShadow = true; g.add(foot);
      const sole = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.27, 0.024, 2, 6, 1), mat.sole);
      sole.quaternion.setFromUnitVectors(V3(0, 1, 0), fd);
      sole.position.copy(fd.clone().multiplyScalar(0.085)).add(plantar.clone().multiplyScalar(0.058));
      sole.castShadow = true; g.add(sole);
      const toe = new THREE.Mesh(new THREE.SphereGeometry(0.05, 20, 14), mat.boot);
      toe.position.copy(fd.clone().multiplyScalar(0.18)).add(plantar.clone().multiplyScalar(0.01)); toe.scale.set(1.05, 0.9, 1);
      toe.castShadow = true; g.add(toe);
      for (let i = 0; i < 4; i++) {
        const l = new THREE.Mesh(new THREE.BoxGeometry(0.052, 0.007, 0.006), mat.metal);
        l.position.copy(fd.clone().multiplyScalar(0.02 + i * 0.03)).add(plantar.clone().multiplyScalar(-0.047));
        l.quaternion.setFromUnitVectors(V3(0, 1, 0), fd);
        g.add(l);
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
      scene.add(decal);
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
