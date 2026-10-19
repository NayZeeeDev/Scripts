/* ═══════════════════════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · field — IV cannulation as a 3D forearm close-up   (apps/field/iv3d.js)

   Runs instead of the 2D vein finder / needle cam when WebGL works (NZA3D.supported()).
   app.js hands the IV step to window.NZAFieldIV3D.handler(ctx) (same interface as the 2D
   handler: enter · tool · key · frame · leave · demo); without WebGL the 2D code runs unchanged.
   Built on core/nza3d.js (skin, layers, bumps, markers, dressing); the props (tourniquet, hand,
   swab, cannula, cap, sharps bin, vein tint, angle gauge) are THREE meshes on S.scene.

   Same Lua contract as the 2D panels:
     Lua → JS  open { mode = 'iv', keys }   step { proc = 'iv', status = 'run', data }
               data { site, siteLabel, map { veins[{ y, bend, width, depth }], best, spot }, angle [lo, hi],
                      attempts, gauge, tourniquetFill, flash, responsive, name, tone?, sex? }
     JS → Lua  field:ivTq { on }   field:result { proc = 'iv', result { site, attempts, angle, secured, failed, score } }
               (field:abort / field:focus / field:skip come from the shared panel, unchanged)

   Steps (procedure HUD, 6):
     1 Tourniquet   hold LMB on the upper-arm ring until the band is tight (or press 1) → ivTq on;
                    the forearm veins fill (raised ridges + a bluish tint) over tourniquetFill s
     2 Find + clean hold LMB on the forearm: the fingers press, a good vein springs back; let go to
                    mark it. Then scrub the mark with the alcohol swab (the wet layer) until the ring fills
     3 Needle in    wheel / ↑ ↓ set the angle (band from the config, shown on the gauge); hold LMB (or the
                    insert key) on the mark: the needle goes in along the vein. Blood in the flashback
                    chamber → let go. Holding on goes through the back wall: bruise, next attempt (step 2)
     4 Advance      hold LMB (or the advance key): the cannula slides off the needle into the vein
     5 Needle out   release the tourniquet (click the band / 1) → ivTq off; hold on the hub: the needle
                    comes out into the sharps bin (with the tourniquet still on: blood spills); hold on the
                    open hub to screw the cap on
     6 Dress        lift the clear film by its border, lay it over the hub (notch at the luer end), rub it
                    down (a palm-wide footprint) → result. Over the device a tent of film fades in.
   Preview: index.html?app=field&mode=iv&stage=<tq|tighten|fill|palpate|swab|insert|flash|advance|tqoff|
            withdraw|cap|dress|carry|laid|done|blown>
   ═══════════════════════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const THREE = window.THREE;
  const MM = 0.001, TAU = Math.PI * 2, DEG = Math.PI / 180;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const hashStr = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rngOf = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);

  let X = null;          // field app internals handed over by app.js (S, ui, L, post, sendResult, keyName, IV2D…)
  let G = null;          // the running close-up
  let failed = false;    // the scene could not be built: the 2D panels for the rest of the session

  /* ─────────── layout of the forearm patch (metres) ───────────
     The patch is a whole cylinder (r = 4 cm) 54 cm long: s runs wrist (left) → elbow / upper arm
     (right), t across the top (+t toward the viewer). The veins of the map lie between V0 and V1. */
  const ARM_W = 0.54, ARM_H = 0.25;
  const S_TQ = 0.165;                       // the tourniquet ring on the upper arm
  const V0 = -0.125, V1 = 0.105;            // map x 0..1 → s
  const T_SPAN = 0.08;                      // map y 0..1 → t
  const WORK = { s: -0.01, w: 0.26, h: 0.11 };
  const TONES = [0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88];
  // ISO 10555-5 cannula colour code by gauge
  const GAUGE_COL = { 14: 0xd8641c, 16: 0x7d858b, 17: 0xe8e8e2, 18: 0x1d7f45, 20: 0xd65a8c, 22: 0x2565b8, 24: 0xe5b51f, 26: 0x6b42a3 };
  const NEEDLE_LEN = 32;                    // mm of catheter (and needle) that can go in
  // home position: the device lies at LIE_DEG with the hub HUB_OFF mm short of the skin along its axis
  // (a few mm of catheter show, the wings rest on the skin instead of sinking into it)
  const LIE_DEG = 11, HUB_OFF = 3.6;
  const HAND_TILT = 1.2, HAND_YAW = -0.8;   // the gloved hand comes in low from the medic's side (bottom right)

  const T = (k, f, vars) => (X ? X.L(`iv3_${k}`, f, vars) : f);
  const T2 = (k, f, vars) => (X ? X.L(k, f, vars) : f);           // keys shared with the 2D panels
  const snd = (name, ...a) => { try { if (NZA.audio && NZA.audio[name]) NZA.audio[name](...a); } catch (e) { /* no audio */ } };

  /* ═════════════════════════ CSS (own file, injected once) ═════════════════════════ */
  const CSS = `
#app-field .fiv-stage{position:absolute;inset:0;overflow:hidden;cursor:crosshair;background:#050607}
#app-field .fiv-stage.grab{cursor:grab}
#app-field .fiv-stage.grabbing{cursor:grabbing}
#app-field.fiv-on .fd-view,#app-field.fiv-on .fd-rack{display:none!important}
#app-field .fiv-tip{display:flex;align-items:flex-start;gap:8px;margin-top:11px;padding:8px 10px 8px 12px;border-radius:8px;background:var(--inset);
  border:1px solid var(--line-hair);position:relative;font-size:11.5px;color:var(--ink-2);line-height:1.45;max-width:60ch}
#app-field .fiv-tip::before{content:'';position:absolute;left:0;top:8px;bottom:8px;width:3px;border-radius:0 3px 3px 0;background:var(--teal);box-shadow:0 0 8px var(--teal)}
#app-field .fiv-tip.amber::before{background:var(--amber);box-shadow:0 0 8px var(--amber)}
#app-field .fiv-tip.red::before{background:var(--red);box-shadow:0 0 8px var(--red)}
#app-field .fiv-tip b{color:var(--white);font-weight:500}
#app-field .fiv-tip:empty{display:none}
.fiv-cur{position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;opacity:0;transition:opacity 140ms}
.fiv-cur.on{opacity:1}
.fiv-cur svg{position:absolute;left:-23px;top:-23px;width:46px;height:46px;transform:rotate(-90deg)}
.fiv-cur .bg{stroke:rgba(255,255,255,.22);fill:none;stroke-width:3}
.fiv-cur .fg{stroke:var(--teal-hi);fill:none;stroke-width:3;stroke-linecap:round;filter:drop-shadow(0 0 4px rgba(15,212,196,.7))}
.fiv-cur.red .fg{stroke:#ff7478;filter:drop-shadow(0 0 4px rgba(229,72,77,.7))}
.fiv-cur.amber .fg{stroke:#f3c35a;filter:drop-shadow(0 0 4px rgba(243,195,90,.6))}
.fiv-cur .tx{position:absolute;left:30px;top:-11px;height:22px;display:inline-flex;align-items:center;padding:0 8px;border-radius:6px;white-space:nowrap;
  font:600 11px var(--font);color:var(--white);background:rgba(12,13,16,.86);border:1px solid var(--hud-line)}
.fiv-cur .tx:empty{display:none}
.fiv-cur .tx.teal{color:var(--teal-hi)} .fiv-cur .tx.red{color:#ff9a9d} .fiv-cur .tx.amber{color:#f3c35a}
`;
  function injectCss() {
    if (document.getElementById('fiv-css')) return;
    const st = document.createElement('style');
    st.id = 'fiv-css'; st.textContent = CSS;
    document.head.appendChild(st);
  }

  /* ═════════════════════════ geometry helpers ═════════════════════════ */
  // tube along a smooth curve through pts; prof(u) → { w, h, e } half-width (binormal), half-height
  // (normal), superellipse exponent. capStart / capEnd close the ends with rounded caps.
  function sweepGeo(pts, prof, o = {}) {
    const seg = o.seg || 24, rad = o.rad || 16, capN = o.capN || 6;
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
    const P = [], Tg = [];
    for (let i = 0; i <= seg; i++) { const u = i / seg; P.push(curve.getPointAt(u)); Tg.push(curve.getTangentAt(u).normalize()); }
    const up = o.up ? o.up.clone() : V3(0, 0, 1);
    let N = up.clone().addScaledVector(Tg[0], -up.dot(Tg[0]));
    if (N.lengthSq() < 1e-10) N = V3(1, 0, 0).addScaledVector(Tg[0], -Tg[0].x);
    N.normalize();
    const Ns = [], Bs = [];
    for (let i = 0; i <= seg; i++) {
      if (i > 0) { N.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(Tg[i - 1], Tg[i])); N.addScaledVector(Tg[i], -N.dot(Tg[i])).normalize(); }
      Ns.push(N.clone()); Bs.push(V3().crossVectors(Tg[i], N).normalize());
    }
    const pr = i => { const r = prof(i / seg); return [r.w, r.h, r.e || 2]; };
    const rings = [];
    if (o.capStart) { const [w, h, e] = pr(0), L = Math.min(w, h) * (o.capLen || 1); for (let k = capN; k >= 1; k--) { const f = k / capN, sc = Math.sqrt(Math.max(0, 1 - f * f)); rings.push([P[0].clone().addScaledVector(Tg[0], -f * L), Ns[0], Bs[0], w * sc, h * sc, e]); } }
    for (let i = 0; i <= seg; i++) { const [w, h, e] = pr(i); rings.push([P[i], Ns[i], Bs[i], w, h, e]); }
    if (o.capEnd) { const [w, h, e] = pr(seg), L = Math.min(w, h) * (o.capLen || 1); for (let k = 1; k <= capN; k++) { const f = k / capN, sc = Math.sqrt(Math.max(0, 1 - f * f)); rings.push([P[seg].clone().addScaledVector(Tg[seg], f * L), Ns[seg], Bs[seg], w * sc, h * sc, e]); } }
    const pos = [], uv = [], idx = [];
    rings.forEach((r, i) => {
      const [c, n, b, w, h, e] = r;
      for (let j = 0; j <= rad; j++) {
        const a = (j / rad) * TAU, ca = Math.cos(a), sa = Math.sin(a);
        const px = Math.sign(ca) * Math.pow(Math.abs(ca), 2 / e) * w, py = Math.sign(sa) * Math.pow(Math.abs(sa), 2 / e) * h;
        pos.push(c.x + b.x * px + n.x * py, c.y + b.y * px + n.y * py, c.z + b.z * px + n.z * py);
        uv.push(j / rad, i / (rings.length - 1));
      }
    });
    for (let i = 0; i < rings.length - 1; i++) for (let j = 0; j < rad; j++) {
      const a = i * (rad + 1) + j, b2 = a + 1, c2 = a + rad + 1, d2 = c2 + 1;
      idx.push(a, c2, b2, b2, c2, d2);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    // weld the seam normals (first / last vertex of every ring)
    const nr = g.attributes.normal;
    for (let i = 0; i < rings.length; i++) {
      const a = i * (rad + 1), b2 = a + rad;
      const x = nr.getX(a) + nr.getX(b2), y = nr.getY(a) + nr.getY(b2), z = nr.getZ(a) + nr.getZ(b2), l = Math.hypot(x, y, z) || 1;
      nr.setXYZ(a, x / l, y / l, z / l); nr.setXYZ(b2, x / l, y / l, z / l);
    }
    return g;
  }
  // box with rounded edges (analytic normals)
  function roundedBox(w, h, d, r, s = 3) {
    r = Math.min(r, w / 2 - 1e-5, h / 2 - 1e-5, d / 2 - 1e-5);
    const n0 = s * 2 + 2;
    const g = new THREE.BoxGeometry(w, h, d, n0, n0, n0);
    const p = g.attributes.position, n = g.attributes.normal;
    const ix = w / 2 - r, iy = h / 2 - r, iz = d / 2 - r;
    const v = V3(), c = V3(), o = V3();
    // grid index i (0..n0) → the outer s steps on each side span the rounded band, the rest the flat part
    const remap = (x, half, inner) => {
      const i = Math.round((x / half + 1) / 2 * n0);
      if (i <= s) return -half + (i / s) * (half - inner);
      if (i >= n0 - s) return half - ((n0 - i) / s) * (half - inner);
      return lerp(-inner, inner, (i - s) / (n0 - 2 * s));
    };
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i);
      v.set(remap(v.x, w / 2, ix), remap(v.y, h / 2, iy), remap(v.z, d / 2, iz));
      c.set(clamp(v.x, -ix, ix), clamp(v.y, -iy, iy), clamp(v.z, -iz, iz));
      o.copy(v).sub(c);
      if (o.lengthSq() > 1e-14) { o.normalize(); v.copy(c).addScaledVector(o, r); n.setXYZ(i, o.x, o.y, o.z); }
      p.setXYZ(i, v.x, v.y, v.z);
    }
    return g;
  }
  // surface of revolution about Y from [radius, y] pairs (millimetres)
  const lathe = (prof, seg = 28) => new THREE.LatheGeometry(prof.map(p => new THREE.Vector2(p[0] * MM, p[1] * MM)), seg);
  const cvs = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; };
  function heightToNormal(hc, strength) {
    const w = hc.width, h = hc.height, src = hc.getContext('2d').getImageData(0, 0, w, h).data;
    const out = cvs(w, h), oc = out.getContext('2d'), id = oc.createImageData(w, h);
    const H = (x, y) => src[(((y + h) % h) * w + ((x + w) % w)) * 4] / 255;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = (H(x + 1, y) - H(x - 1, y)) * strength, dy = (H(x, y + 1) - H(x, y - 1)) * strength;
      const l = Math.hypot(dx, dy, 1), i = (y * w + x) * 4;
      id.data[i] = (-dx / l * 0.5 + 0.5) * 255; id.data[i + 1] = (dy / l * 0.5 + 0.5) * 255; id.data[i + 2] = (1 / l * 0.5 + 0.5) * 255; id.data[i + 3] = 255;
    }
    oc.putImageData(id, 0, 0);
    return out;
  }
  // nitrile grain (fine pebbled noise) as a height canvas
  function grainCanvas(n, seed, cells) {
    const c = cvs(n, n), x = c.getContext('2d'), R = rngOf(seed);
    x.fillStyle = '#808080'; x.fillRect(0, 0, n, n);
    for (let i = 0; i < cells; i++) {
      const px = R() * n, py = R() * n, r = 0.6 + R() * 1.6, v = Math.round(110 + R() * 90);
      x.fillStyle = `rgba(${v},${v},${v},0.55)`;
      for (const ox of [-n, 0, n]) for (const oy of [-n, 0, n]) { x.beginPath(); x.arc(px + ox, py + oy, r, 0, TAU); x.fill(); }
    }
    return c;
  }
  // woven elastic strap: albedo (stripes + edge bands) and a height for the weave
  function strapCanvas() {
    const w = 64, h = 256, a = cvs(w, h), ax = a.getContext('2d'), ht = cvs(w, h), hx = ht.getContext('2d');
    ax.fillStyle = '#3d74ad'; ax.fillRect(0, 0, w, h);
    ax.fillStyle = 'rgba(255,255,255,.08)'; for (let y = 0; y < h; y += 4) ax.fillRect(0, y, w, 1);
    ax.fillStyle = '#244f80'; ax.fillRect(0, 0, w, 5); ax.fillRect(0, h - 5, w, 5);
    ax.fillStyle = 'rgba(230,240,250,.55)'; ax.fillRect(0, 9, w, 2); ax.fillRect(0, h - 11, w, 2);
    hx.fillStyle = '#808080'; hx.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 2) { hx.fillStyle = y % 4 ? '#5a5a5a' : '#a8a8a8'; hx.fillRect(0, y, w, 1); }
    for (let x = 0; x < w; x += 3) { hx.fillStyle = 'rgba(0,0,0,.18)'; hx.fillRect(x, 0, 1, h); }
    return { albedo: a, height: ht };
  }
  // label printing (generic text only)
  function labelCanvas(draw, w, h) { const c = cvs(w, h); draw(c.getContext('2d'), w, h); return c; }

  /* ═════════════════════════ props ═════════════════════════ */
  // clip = the skin plane at the entry point: the part of the needle / catheter under the skin is cut
  // away (at a flat angle the first millimetre under the skin otherwise bleeds through the depth test)
  function materials(S, gauge, keep, clip, clipN) {
    const tex = (c, srgb, rep) => { const t = keep(new THREE.CanvasTexture(c)); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; if (srgb) t.encoding = THREE.sRGBEncoding; if (rep) t.repeat.set(rep[0], rep[1]); return t; };
    const gloveN = tex(heightToNormal(grainCanvas(128, 31, 900), 2.2), false, [3, 3]);
    const strap = strapCanvas();
    const strapA = tex(strap.albedo, true), strapN = tex(heightToNormal(strap.height, 1.4), false);
    const pad = cvs(128, 128), px = pad.getContext('2d'), R = rngOf(77);
    px.fillStyle = '#f5f6f5'; px.fillRect(0, 0, 128, 128);
    for (let i = 0; i < 500; i++) { px.strokeStyle = `rgba(${200 + R() * 40},${205 + R() * 40},${205 + R() * 40},.5)`; px.lineWidth = 0.6; px.beginPath(); const x0 = R() * 128, y0 = R() * 128, a = R() * TAU; px.moveTo(x0, y0); px.lineTo(x0 + Math.cos(a) * 9, y0 + Math.sin(a) * 9); px.stroke(); }
    const padT = tex(pad, true);
    const hub = new THREE.Color(GAUGE_COL[gauge] || GAUGE_COL[18]).convertSRGBToLinear();   // the ISO colour as printed
    const M = {
      glove: keep(new THREE.MeshPhysicalMaterial({ color: 0x2236a2, roughness: 0.5, normalMap: gloveN, normalScale: new THREE.Vector2(0.35, 0.35), sheen: 0.12, sheenRoughness: 0.55, sheenColor: new THREE.Color(0x4a62c0), clearcoat: 0.22, clearcoatRoughness: 0.42, envMapIntensity: 0.7 })),
      sleeve: keep(new THREE.MeshPhysicalMaterial({ color: 0x1d3a4a, roughness: 0.92, sheen: 0.5, sheenColor: new THREE.Color(0x6aa4b4) })),
      steel: keep(new THREE.MeshPhysicalMaterial({ color: 0xe4e9ed, roughness: 0.18, metalness: 0.95, envMapIntensity: 1.8, clearcoat: 0.3, clearcoatRoughness: 0.15, clippingPlanes: [clipN], clipShadows: true })),
      clearHard: keep(new THREE.MeshPhysicalMaterial({ color: 0xf4fbff, roughness: 0.06, transparent: true, opacity: 0.32, clearcoat: 1, clearcoatRoughness: 0.03, depthWrite: false, side: THREE.DoubleSide, envMapIntensity: 1.4 })),
      cath: keep(new THREE.MeshPhysicalMaterial({ color: 0xf2f5f6, roughness: 0.22, transparent: true, opacity: 0.78, clearcoat: 0.8, clearcoatRoughness: 0.1, clippingPlanes: [clip], clipShadows: true })),
      // clear film shrunk over the hub (the dressing's tent)
      film: keep(new THREE.MeshPhysicalMaterial({ color: 0xf6fafc, roughness: 0.1, transparent: true, opacity: 0, clearcoat: 1, clearcoatRoughness: 0.06, depthWrite: false, side: THREE.DoubleSide, envMapIntensity: 1.6 })),
      hub: keep(new THREE.MeshPhysicalMaterial({ color: hub, roughness: 0.34, clearcoat: 0.4, clearcoatRoughness: 0.22 })),
      hubLight: keep(new THREE.MeshPhysicalMaterial({ color: hub.clone().lerp(new THREE.Color(0xffffff), 0.12), roughness: 0.38, clearcoat: 0.35 })),
      white: keep(new THREE.MeshPhysicalMaterial({ color: 0xf1f3f4, roughness: 0.36, clearcoat: 0.5, clearcoatRoughness: 0.3 })),
      grip: keep(new THREE.MeshPhysicalMaterial({ color: 0xe6eaec, roughness: 0.5, clearcoat: 0.2 })),
      blood: keep(new THREE.MeshPhysicalMaterial({ color: 0x5c0308, roughness: 0.22, clearcoat: 0.9, clearcoatRoughness: 0.12 })),
      strap: keep(new THREE.MeshPhysicalMaterial({ map: strapA, normalMap: strapN, normalScale: new THREE.Vector2(0.7, 0.7), roughness: 0.82, sheen: 0.6, sheenRoughness: 0.6, sheenColor: new THREE.Color(0x9cc4ea) })),
      buckle: keep(new THREE.MeshPhysicalMaterial({ color: 0x23272a, roughness: 0.42, clearcoat: 0.35, clearcoatRoughness: 0.3 })),
      button: keep(new THREE.MeshPhysicalMaterial({ color: 0x9aa4aa, roughness: 0.38, clearcoat: 0.4 })),
      yellow: keep(new THREE.MeshPhysicalMaterial({ color: 0xf0c22c, roughness: 0.42, clearcoat: 0.35, clearcoatRoughness: 0.3 })),
      lid: keep(new THREE.MeshPhysicalMaterial({ color: 0xd9531e, roughness: 0.4, clearcoat: 0.35 })),
      dark: keep(new THREE.MeshPhysicalMaterial({ color: 0x0c0d0e, roughness: 0.7 })),
      pad: keep(new THREE.MeshPhysicalMaterial({ map: padT, color: 0xffffff, roughness: 0.82, clearcoat: 0.25, clearcoatRoughness: 0.4, sheen: 0.4, sheenColor: new THREE.Color(0xffffff) })),
    };
    return M;
  }

  // gloved right hand pressing with two fingertips. Tool frame (engine convention): origin = the
  // contact point between the index and middle pads, +Y toward the wrist, pads face -Z, thumb on +X.
  function buildHand(S, M, keep) {
    const g = new THREE.Group(), inner = new THREE.Group();
    g.add(inner);
    const P = (x, y, z) => V3(x * MM, y * MM, z * MM);
    // knuckles (PIP / DIP) bulge a little, the pad end flattens
    const finger = (pts, r0, r1, flat = 0.88, joints = [0.42, 0.7]) => {
      const geo = keep(sweepGeo(pts.map(p => P(...p)), u => {
        let r = lerp(r0, r1, u);
        joints.forEach(j => { r *= 1 + 0.075 * Math.exp(-Math.pow((u - j) / 0.05, 2)) - 0.03 * Math.exp(-Math.pow((u - j - 0.12) / 0.06, 2)); });
        r *= MM;
        return { w: r, h: r * lerp(flat, flat * 0.9, smooth(0.75, 1, u)), e: 2.15 };
      }, { seg: 34, rad: 18, up: V3(0, 0, 1), capStart: true, capEnd: true, capLen: 0.95 }));
      const m = new THREE.Mesh(geo, M.glove); inner.add(m); return m;
    };
    // index and middle: nearly straight, slightly apart, pads on the skin
    finger([[9.5, 94, 11], [10, 66, 11.5], [10.4, 46, 12], [10.4, 27, 9.5], [10, 11, 7.2], [9.6, 3, 6.8]], 9.0, 7.0);
    finger([[-8.5, 98, 11], [-8.8, 70, 11.5], [-9.4, 47, 12], [-9.6, 27, 9.5], [-9.4, 11, 7.2], [-9.2, 2.5, 6.8]], 9.3, 7.2);
    // ring and little: loosely flexed under the palm, tips held off the skin (a deep curl would dip
    // into the near side of the forearm when the hand comes in low)
    finger([[-25, 94, 12], [-27, 72, 10], [-28.5, 57, 6.5], [-29, 45, 2.5], [-28.5, 37, 1]], 8.8, 7.0, 0.88, [0.4, 0.68]);
    finger([[-40, 88, 13], [-42.5, 70, 11], [-43.5, 58, 7.5], [-43.5, 48, 4.5], [-43, 42, 3.5]], 7.8, 6.4, 0.88, [0.42, 0.7]);
    // thumb tucked along the side of the index finger
    finger([[30, 134, 9], [40, 115, 3.5], [42.5, 97, 0], [39, 80, -1.5], [34, 70, -1]], 10.6, 8.4, 0.84, [0.55]);
    // palm: squared ellipsoid with a slightly arched back
    const palmG = keep(new THREE.SphereGeometry(1, 40, 28));
    {
      const p = palmG.attributes.position;
      for (let i = 0; i < p.count; i++) {
        let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
        const sq = v => Math.sign(v) * Math.pow(Math.abs(v), 0.8);
        x = sq(x) * 45; y = sq(y) * 44; z = sq(z) * 12;
        x *= lerp(0.92, 1.0, clamp((y + 44) / 88, 0, 1));
        if (z > 0) z += (1 - Math.pow(x / 46, 2)) * 2.2;
        p.setXYZ(i, x * MM, y * MM, z * MM);
      }
      palmG.computeVertexNormals();
    }
    const palm = new THREE.Mesh(palmG, M.glove); palm.position.copy(P(-7, 130, 15)); inner.add(palm);
    const thenar = new THREE.Mesh(keep(new THREE.SphereGeometry(1, 28, 18)), M.glove);
    thenar.scale.set(17 * MM, 30 * MM, 11 * MM); thenar.position.copy(P(28, 128, 8)); thenar.rotation.z = -0.3; inner.add(thenar);
    // wrist, rolled glove cuff, gown sleeve
    inner.add(new THREE.Mesh(keep(sweepGeo([P(-7, 160, 15), P(-7, 190, 16), P(-7, 222, 17)], u => ({ w: lerp(33, 30, u) * MM, h: lerp(16, 19, u) * MM, e: 2.3 }), { seg: 8, rad: 28 })), M.glove));
    const cuff = new THREE.Mesh(keep(new THREE.TorusGeometry(31.5 * MM, 3.2 * MM, 10, 36)), M.glove);
    cuff.rotation.x = Math.PI / 2; cuff.scale.set(1, 0.66, 1); cuff.position.copy(P(-7, 222, 17)); inner.add(cuff);
    const slv = new THREE.Mesh(keep(new THREE.CylinderGeometry(40 * MM, 36 * MM, 210 * MM, 36, 1, false)), M.sleeve);
    slv.scale.set(1, 1, 0.74); slv.position.copy(P(-7, 330, 19)); inner.add(slv);
    inner.scale.setScalar(0.7);
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    g.visible = false;
    S.scene.add(g);
    return { group: g, inner, name: 'iv3d_hand', press: 0, _p: V3(), _q: new THREE.Quaternion(), _init: false,
      pose: { lift: 0.006, pressLift: -0.0009, tilt: HAND_TILT, yaw: HAND_YAW, roll: 0, shadow: 0.06 },
      tipWorld: () => g.getWorldPosition(V3()), set() {} };
  }

  // folded alcohol prep pad under the gloved fingertips. The tool has the hand's pose; the pad is
  // turned into the skin plane (local normal = (0, cos tilt, sin tilt)) and the hand rides on top of it.
  const SWAB_T = 2.2 * MM, SWAB_R = 0.0085;   // pad thickness · radius round the mark that must be cleaned
  function buildSwab(S, M, keep) {
    const g = new THREE.Group();
    const nrm = V3(0, Math.cos(HAND_TILT), Math.sin(HAND_TILT));
    const padG = new THREE.Group();
    padG.quaternion.setFromUnitVectors(V3(0, 1, 0), nrm);
    padG.position.copy(nrm).multiplyScalar(0.0001);
    const pad = new THREE.Mesh(keep(roundedBox(26 * MM, SWAB_T, 26 * MM, 0.9 * MM, 2)), M.pad);
    pad.position.set(0, SWAB_T / 2, 3 * MM); pad.castShadow = true; pad.receiveShadow = true; padG.add(pad);
    const fold = new THREE.Mesh(keep(new THREE.BoxGeometry(26 * MM, 0.25 * MM, 0.5 * MM)), M.grip);
    fold.position.set(0, SWAB_T + 0.05 * MM, 7 * MM); padG.add(fold);
    g.add(padG);
    g.visible = false;
    S.scene.add(g);
    return { group: g, name: 'iv3d_swab', press: 0, _p: V3(), _q: new THREE.Quaternion(), _init: false, lift: nrm.clone().multiplyScalar(SWAB_T * 0.9),
      pose: { lift: 0.004, pressLift: -0.0006, tilt: HAND_TILT, yaw: HAND_YAW, roll: 0, shadow: 0.05 },
      tipWorld: () => g.getWorldPosition(V3()), set() {} };
  }

  // luer cap: open end at the origin, body along +Y
  function buildCap(S, M, keep) {
    const g = new THREE.Group();
    const prof = [[1.25, 0], [1.9, 0], [2.05, 0.5], [2.3, 0.6], [2.3, 6.4], [2.7, 6.6], [2.7, 8.4], [2.2, 8.9], [0, 9]];
    const body = new THREE.Mesh(keep(lathe(prof, 24)), M.white); body.castShadow = true; g.add(body);
    for (let k = 0; k < 6; k++) {
      const rib = new THREE.Mesh(keep(new THREE.BoxGeometry(0.6 * MM, 5.2 * MM, 0.8 * MM)), M.white);
      const a = (k / 6) * TAU; rib.position.set(Math.cos(a) * 2.45 * MM, 3.6 * MM, Math.sin(a) * 2.45 * MM); rib.rotation.y = -a; g.add(rib);
    }
    g.visible = false;
    S.scene.add(g);
    return { group: g, name: 'iv3d_cap', press: 0, _p: V3(), _q: new THREE.Quaternion(), _init: false,
      pose: { lift: 0.009, pressLift: 0.004, tilt: 0.55, yaw: -0.5, roll: 0, shadow: 0.012 },
      tipWorld: () => g.getWorldPosition(V3()), set() {} };
  }

  // over-the-needle IV cannula. Local frame: needle tip at the origin, device axis +Y (toward the
  // hub), +Z = top (injection port), wings along ±X. needleG slides back, cathG slides forward.
  function buildCannula(S, M, keep) {
    const g = new THREE.Group(), needleG = new THREE.Group(), cathG = new THREE.Group();
    g.add(needleG, cathG);
    const add = (parent, geo, mat, cast = true) => { const m = new THREE.Mesh(keep(geo), mat); m.castShadow = cast; m.receiveShadow = true; parent.add(m); return m; };
    const nr = 0.62;
    const shaft = new THREE.CylinderGeometry(nr * MM, nr * MM, 47 * MM, 12, 1, true); shaft.translate(0, (1.7 + 23.5) * MM, 0);
    add(needleG, shaft, M.steel);
    const tip = new THREE.ConeGeometry(nr * MM, 1.7 * MM, 12, 1, false); tip.rotateX(Math.PI); tip.translate(0, 0.85 * MM, 0);
    add(needleG, tip, M.steel);
    // flashback chamber (clear), the blood column inside, vent plug, ribbed grip with finger tabs
    add(needleG, lathe([[1.0, 47.2], [2.7, 47.5], [2.95, 48.2], [2.95, 59.4], [2.7, 60.1]], 28), M.clearHard, false);
    const blood = add(needleG, (() => { const c = new THREE.CylinderGeometry(2.25 * MM, 2.25 * MM, 11.2 * MM, 20); c.translate(0, 5.6 * MM, 0); return c; })(), M.blood, false);
    blood.position.y = 48.0 * MM; blood.scale.y = 0.001;
    const plug = add(needleG, new THREE.CylinderGeometry(2.8 * MM, 2.8 * MM, 1.6 * MM, 24), M.white); plug.position.y = 60.9 * MM;
    const gp = [[0.5, 61.6], [3.2, 61.7]];
    for (let k = 0; k < 8; k++) { const y = 62.6 + k * 1.55; gp.push([3.2, y], [3.55, y + 0.45], [3.55, y + 0.85], [3.2, y + 1.3]); }
    gp.push([3.2, 76], [2.7, 77], [0.5, 77.2]);
    add(needleG, lathe(gp, 28), M.grip);
    [-1, 1].forEach(sd => { const tab = add(needleG, roundedBox(3.2 * MM, 11 * MM, 1.4 * MM, 0.6 * MM, 1), M.grip); tab.position.set(sd * 4.6 * MM, 67 * MM, 0); });
    // catheter: translucent tube with a tapered tip, coloured hub, wings, injection port
    add(cathG, lathe([[0.6, 1.45], [0.68, 2.6], [0.69, 33.6]], 14), M.cath, false);
    // hub with its luer bore (seen once the needle is out)
    add(cathG, lathe([[0.7, 33.5], [1.5, 34.1], [2.3, 35.4], [2.85, 36.8], [3.05, 38.2], [3.05, 46.1], [3.45, 46.3], [3.45, 47.3], [2.7, 47.45], [1.95, 47.4], [1.9, 41.5], [0.75, 39.8]], 28), M.hub);
    const wing = new THREE.Shape();
    wing.moveTo(2.2, 36.2); wing.lineTo(7.4, 36.8); wing.quadraticCurveTo(9.6, 37.3, 9.7, 39.8); wing.quadraticCurveTo(9.6, 42.4, 7.4, 42.8); wing.lineTo(2.2, 43.6); wing.lineTo(2.2, 36.2);
    const wg = new THREE.ExtrudeGeometry(wing, { depth: 0.6, bevelEnabled: true, bevelThickness: 0.18, bevelSize: 0.22, bevelSegments: 2, curveSegments: 10 });
    wg.scale(MM, MM, MM); wg.translate(0, 0, -2.2 * MM);
    add(cathG, wg, M.hub);
    const w2 = add(cathG, wg.clone(), M.hub); w2.scale.x = -1;
    const port = add(cathG, new THREE.CylinderGeometry(1.7 * MM, 2.0 * MM, 3.6 * MM, 20), M.hub); port.rotation.x = Math.PI / 2; port.position.set(0, 40.6 * MM, 4.2 * MM);
    const portCap = add(cathG, new THREE.CylinderGeometry(2.1 * MM, 2.1 * MM, 1.4 * MM, 20), M.hubLight); portCap.rotation.x = Math.PI / 2; portCap.position.set(0, 40.6 * MM, 6.3 * MM);
    const hinge = add(cathG, roundedBox(1.4 * MM, 2.6 * MM, 1.0 * MM, 0.35 * MM, 1), M.hubLight); hinge.position.set(0, 43.0 * MM, 5.8 * MM);
    // gauge print on the wing (generic)
    const lab = labelCanvas((x, w, h) => { x.clearRect(0, 0, w, h); x.fillStyle = 'rgba(255,255,255,.85)'; x.font = '700 40px Lexend, Arial, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(`${S.__gauge || 18}G`, w / 2, h / 2); }, 128, 64);
    const lt = keep(new THREE.CanvasTexture(lab)); lt.encoding = THREE.sRGBEncoding;
    const lm = keep(new THREE.MeshBasicMaterial({ map: lt, transparent: true, depthWrite: false }));
    const lp = new THREE.Mesh(keep(new THREE.PlaneGeometry(4.6 * MM, 2.3 * MM)), lm); lp.position.set(6.2 * MM, 39.8 * MM, -1.38 * MM); lp.rotation.z = -Math.PI / 2; cathG.add(lp);
    g.visible = false;
    S.scene.add(g);
    return { group: g, needleG, cathG, blood, cap: null };
  }

  // the tourniquet: an elastic strap round the upper arm + a push-button buckle. set(arc, r) rebuilds
  // the strap: arc = how far round it is wrapped (rad), r = inner radius (arm radius + slack)
  function buildTourniquet(S, M, keep) {
    const g = new THREE.Group();
    const R = S.shape.R, cy = -R, bw = 0.025, th = 0.0017, NA = 120, NP = 14, aB = -0.42;
    const prof = [];
    for (let k = 0; k < NP; k++) { const a = (k / NP) * TAU; prof.push([Math.sign(Math.cos(a)) * Math.pow(Math.abs(Math.cos(a)), 0.22) * bw / 2, Math.sign(Math.sin(a)) * Math.pow(Math.abs(Math.sin(a)), 0.22) * th / 2]); }
    const geo = keep(new THREE.BufferGeometry());
    const pos = new Float32Array((NA + 1) * NP * 3), uv = new Float32Array((NA + 1) * NP * 2), idx = [];
    for (let i = 0; i < NA; i++) for (let k = 0; k < NP; k++) {
      const a = i * NP + k, b = i * NP + (k + 1) % NP, c = a + NP, d = b + NP;
      idx.push(a, b, c, b, d, c);
    }
    for (let i = 0; i <= NA; i++) for (let k = 0; k < NP; k++) { uv[(i * NP + k) * 2] = k / NP; uv[(i * NP + k) * 2 + 1] = i / NA * 6; }
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geo.setIndex(idx);
    const strap = new THREE.Mesh(geo, M.strap); strap.castShadow = true; strap.receiveShadow = true; strap.frustumCulled = false;
    g.add(strap);
    const buckle = new THREE.Group();
    const body = new THREE.Mesh(keep(roundedBox(0.034, 0.0075, 0.02, 0.0028, 3)), M.buckle); body.castShadow = true; buckle.add(body);
    const btn = new THREE.Mesh(keep(new THREE.CylinderGeometry(0.0055, 0.006, 0.0022, 28)), M.button); btn.position.y = 0.0045; btn.castShadow = true; buckle.add(btn);
    const ridge = new THREE.Mesh(keep(roundedBox(0.03, 0.0016, 0.0035, 0.0007, 1)), M.buckle); ridge.position.set(0, 0.0038, -0.0078); buckle.add(ridge);
    g.add(buckle);
    // free tail of the strap sticking out of the buckle
    const tail = new THREE.Mesh(keep(roundedBox(bw * 0.92, th, 0.03, 0.0007, 1)), M.strap); tail.castShadow = true; g.add(tail);
    const api = { group: g, arc: 0, r: R + 0.006, aB };
    api.set = (arc, r) => {
      api.arc = arc; api.r = r;
      for (let i = 0; i <= NA; i++) {
        const a = aB + (i / NA) * arc;
        // the overlapping turn rides on top of the first one
        const over = a > aB + TAU ? th * 1.05 : 0;
        for (let k = 0; k < NP; k++) {
          const rr = r + th / 2 + prof[k][1] + over, j = (i * NP + k) * 3;
          pos[j] = S_TQ + prof[k][0]; pos[j + 1] = cy + rr * Math.cos(a); pos[j + 2] = rr * Math.sin(a);
        }
      }
      geo.attributes.position.needsUpdate = true;
      geo.computeVertexNormals();
      geo.computeBoundingSphere();
      // buckle sits where the strap closes, on top of both turns
      const ab = aB, rb = r + th * 2.1 + 0.0036;
      buckle.position.set(S_TQ, cy + rb * Math.cos(ab), rb * Math.sin(ab));
      buckle.rotation.set(ab, 0, 0);
      buckle.visible = arc > 1.2;
      const at = aB - 0.12, rt = r + th * 1.6;
      tail.position.set(S_TQ, cy + rt * Math.cos(at), rt * Math.sin(at));
      tail.rotation.set(at, 0, 0);
      tail.position.addScaledVector(V3(0, -Math.sin(at), Math.cos(at)), -0.016);
      tail.visible = arc > TAU - 0.1;
    };
    S.scene.add(g);
    g.visible = false;
    return api;
  }

  // sharps bin on the sheet behind the arm (label: generic text + glyph only)
  function buildSharps(S, M, keep, at) {
    const g = new THREE.Group();
    const add = (geo, mat, x, y, z) => { const m = new THREE.Mesh(keep(geo), mat); m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; g.add(m); return m; };
    add(roundedBox(0.072, 0.082, 0.058, 0.007, 3), M.yellow, 0, 0.041, 0);
    add(roundedBox(0.077, 0.015, 0.063, 0.005, 2), M.lid, 0, 0.088, 0);
    add(roundedBox(0.04, 0.003, 0.012, 0.0014, 1), M.dark, 0.006, 0.0955, 0.006);
    const lab = labelCanvas((x, w, h) => {
      x.fillStyle = '#f7f5ee'; x.fillRect(0, 0, w, h);
      x.fillStyle = '#16181a'; x.font = '800 54px Lexend, Arial, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
      x.fillText('SHARPS', w / 2 + 34, h * 0.36);
      x.font = '600 22px Lexend, Arial, sans-serif'; x.fillText('NEEDLES ONLY · DO NOT OVERFILL', w / 2, h * 0.78);
      // trefoil-like hazard glyph
      x.save(); x.translate(64, h * 0.38); x.strokeStyle = '#16181a'; x.lineWidth = 6;
      for (let k = 0; k < 3; k++) { x.rotate(TAU / 3); x.beginPath(); x.arc(0, -17, 13, 0, TAU); x.stroke(); }
      x.beginPath(); x.arc(0, 0, 6, 0, TAU); x.fill(); x.restore();
      x.fillStyle = '#16181a'; x.fillRect(0, h * 0.6, w, 3);
    }, 512, 256);
    const lt = keep(new THREE.CanvasTexture(lab)); lt.encoding = THREE.sRGBEncoding; lt.anisotropy = 4;
    const lm = keep(new THREE.MeshPhysicalMaterial({ map: lt, roughness: 0.5, clearcoat: 0.3 }));
    add(new THREE.PlaneGeometry(0.06, 0.03), lm, 0, 0.044, 0.0293);
    g.position.copy(at);
    g.rotation.y = 0.22;
    g.scale.setScalar(0.88);
    S.scene.add(g);
    return { group: g, mouth: () => g.localToWorld(V3(0.006, 0.1, 0.006)) };
  }

  // the bluish tint of filled veins: a multiply-blended sheet that hugs the skin over the vein area
  function buildVeinTint(S, veins, tone, keep) {
    const s0 = V0 - 0.012, s1 = V1 + 0.012, t0 = -0.052, t1 = 0.052;
    const cw = 1024, ch = Math.round(cw * (t1 - t0) / (s1 - s0));
    const pxS = s => (s - s0) / (s1 - s0) * cw, pxT = t => (t - t0) / (t1 - t0) * ch, pxM = m => m / (s1 - s0) * cw;
    const c = cvs(cw, ch), x = c.getContext('2d');
    const R = rngOf(4242);
    // the main veins per pixel from the same model as the ridges: strongest where they stand out,
    // a soft edge, a faint wider shadow of the deeper part of the vessel
    const id = x.createImageData(cw, ch), dd = id.data;
    for (let px = 0; px < cw; px++) {
      const s = s0 + (px + 0.5) / cw * (s1 - s0), u = (s - V0) / (V1 - V0);
      const cols = veins.map(v => {
        const uc = clamp(u, 0, 1), p = v.at(uc), q = v.at(clamp(uc + 0.01, 0, 1)), r = v.at(clamp(uc - 0.01, 0, 1));
        const sl = (q[1] - r[1]) / Math.max(1e-6, q[0] - r[0]);
        return { t: p[1], k: 1 / Math.sqrt(1 + sl * sl), a: (u < -0.02 || u > 1.02 ? 0 : v.show(uc)) * (0.8 + 0.2 * v.vis), w: v.rv * 1.35, w2: v.rv * 2.8 };
      });
      for (let py = 0; py < ch; py++) {
        const t = t0 + (py + 0.5) / ch * (t1 - t0);
        let a = 0;
        for (const cv of cols) {
          if (cv.a <= 0) continue;
          const d = Math.abs(t - cv.t) * cv.k;
          a = Math.max(a, cv.a * (Math.exp(-(d / cv.w) * (d / cv.w)) * 0.86 + Math.exp(-(d / cv.w2) * (d / cv.w2)) * 0.14));
        }
        const o = (py * cw + px) * 4;
        dd[o] = dd[o + 1] = dd[o + 2] = 255; dd[o + 3] = Math.round(clamp(a, 0, 1) * 255);
      }
    }
    x.putImageData(id, 0, 0);
    // faint tributaries joining the main veins
    x.lineCap = 'round';
    for (let k = 0; k < 10; k++) {
      const v = veins[Math.floor(R() * veins.length)], xa = lerp(v.ua + 0.05, v.ub - 0.05, R());
      const pa = v.at(xa), dir = R() < 0.5 ? -1 : 1, len = 0.012 + R() * 0.026;
      x.strokeStyle = `rgba(255,255,255,${(0.08 + R() * 0.1) * v.show(xa)})`; x.lineWidth = pxM(0.0008 + R() * 0.0006);
      x.beginPath(); x.moveTo(pxS(pa[0]), pxT(pa[1]));
      x.quadraticCurveTo(pxS(pa[0] + len * 0.5), pxT(pa[1] + dir * len * 0.22 + (R() - 0.5) * 0.005), pxS(pa[0] + len * (0.9 + R() * 0.4)), pxT(pa[1] + dir * len * (0.45 + R() * 0.4)));
      x.stroke();
    }
    const tx = keep(new THREE.CanvasTexture(c)); tx.anisotropy = 4; tx.generateMipmaps = true;
    // "modulate 2x" blend (2 · src · dst, 0.5 = no change): the red of the skin drops and its blue lifts a
    // little, so a filled vein reads blue-green through the skin instead of a grey smudge (a plain
    // multiply can only darken). Dark skin: the veins barely change the colour.
    const col = new THREE.Color().setRGB(lerp(0.66, 0.88, tone) / 2, lerp(0.8, 0.9, tone) / 2, lerp(1.15, 0.97, tone) / 2);
    const mat = keep(new THREE.ShaderMaterial({
      uniforms: { tMap: { value: tx }, uAmt: { value: 0 }, uCol: { value: col } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: 'uniform sampler2D tMap; uniform float uAmt; uniform vec3 uCol; varying vec2 vUv;\nvoid main(){ float a = clamp(texture2D(tMap, vUv).a * uAmt, 0.0, 1.0); gl_FragColor = vec4(mix(vec3(0.5), uCol, a), 1.0); }',
      transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
      blendSrc: THREE.DstColorFactor, blendDst: THREE.SrcColorFactor, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    }));
    const NS = 170, NT = 54, nv = (NS + 1) * (NT + 1);
    const base = new Float32Array(nv * 3), nrm = new Float32Array(nv * 3), full = new Float32Array(nv), pos = new Float32Array(nv * 3), uv = new Float32Array(nv * 2);
    const P = V3(), N = V3();
    let k = 0;
    for (let j = 0; j <= NT; j++) for (let i = 0; i <= NS; i++, k++) {
      const s = lerp(s0, s1, i / NS), t = lerp(t0, t1, j / NT);
      S._surf(s, t, P, N);
      base[k * 3] = P.x; base[k * 3 + 1] = P.y; base[k * 3 + 2] = P.z; nrm[k * 3] = N.x; nrm[k * 3 + 1] = N.y; nrm[k * 3 + 2] = N.z;
      uv[k * 2] = i / NS; uv[k * 2 + 1] = 1 - j / NT;
      // ridge height at full fill (same profile as the engine's bumps)
      let h = 0;
      for (const v of veins) for (const b of v.bumps) {
        const dx = (s - b.s) / b.r, dy = (t - b.t) / b.r, d2 = dx * dx + dy * dy;
        if (d2 < 1) h += b.h * (1 - d2) * (1 - d2);
      }
      full[k] = h;
    }
    const idx = [];
    for (let j = 0; j < NT; j++) for (let i = 0; i < NS; i++) { const a = j * (NS + 1) + i, b = a + 1, c2 = a + NS + 1, d = c2 + 1; idx.push(a, c2, b, b, c2, d); }
    const geo = keep(new THREE.BufferGeometry());
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geo.setIndex(idx);
    const mesh = new THREE.Mesh(geo, mat);
    mesh.renderOrder = 2; mesh.frustumCulled = false;
    S.scene.add(mesh);
    const api = { mesh, mat, k: -1 };
    api.set = (fill, amt) => {
      mat.uniforms.uAmt.value = amt;
      if (Math.abs(fill - api.k) < 0.004) return;
      api.k = fill;
      const off = 0.00028;
      for (let i = 0; i < nv; i++) {
        const h = full[i] * fill + off;
        pos[i * 3] = base[i * 3] + nrm[i * 3] * h; pos[i * 3 + 1] = base[i * 3 + 1] + nrm[i * 3 + 1] * h; pos[i * 3 + 2] = base[i * 3 + 2] + nrm[i * 3 + 2] * h;
      }
      geo.attributes.position.needsUpdate = true;
      geo.computeBoundingSphere();
    };
    api.set(0, 0);
    return api;
  }

  // protractor in the plane of the needle: origin at the entry point, 0° along the skin (back toward
  // the hub), the band from the config in teal, the needle's angle as a line
  function buildGauge(S, keep) {
    const n = 256, c = cvs(n, n), x = c.getContext('2d');
    const tx = keep(new THREE.CanvasTexture(c)); tx.encoding = THREE.sRGBEncoding;
    const mat = keep(new THREE.MeshBasicMaterial({ map: tx, transparent: true, depthWrite: false, side: THREE.DoubleSide, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -4 }));
    const size = 0.034;
    const geo = keep(new THREE.PlaneGeometry(size, size)); geo.translate(-size / 2, size / 2, 0);   // origin = bottom-right corner
    const mesh = new THREE.Mesh(geo, mat); mesh.renderOrder = 8; mesh.visible = false;
    S.scene.add(mesh);
    let last = '';
    const api = { mesh };
    api.draw = (deg, band) => {
      const key = `${Math.round(deg)}|${band[0]}|${band[1]}`;
      if (key === last) return;
      last = key;
      x.clearRect(0, 0, n, n);
      // origin bottom-right; 0° points left (back along the skin toward the hub), angles rise upward
      const O = [n - 10, n - 10], R1 = n - 34, R0 = R1 * 0.38, toXY = (a, r) => [O[0] - Math.cos(a) * r, O[1] - Math.sin(a) * r];
      // band wedge
      x.beginPath(); x.moveTo(O[0], O[1]); x.arc(O[0], O[1], R1, Math.PI + band[0] * DEG, Math.PI + band[1] * DEG); x.closePath();
      x.fillStyle = 'rgba(15,212,196,.16)'; x.fill();
      x.strokeStyle = 'rgba(15,212,196,.75)'; x.lineWidth = 2;
      [band[0], band[1]].forEach(a => { const [ex, ey] = toXY(a * DEG, R1); x.beginPath(); x.moveTo(O[0], O[1]); x.lineTo(ex, ey); x.stroke(); });
      // scale arc + ticks every 5°
      x.strokeStyle = 'rgba(255,255,255,.55)'; x.lineWidth = 2;
      x.beginPath(); x.arc(O[0], O[1], R1, Math.PI, Math.PI + 50 * DEG); x.stroke();
      for (let a = 0; a <= 50; a += 5) {
        const [ax, ay] = toXY(a * DEG, R1), [bx, by] = toXY(a * DEG, R1 - (a % 15 ? 8 : 14));
        x.beginPath(); x.moveTo(ax, ay); x.lineTo(bx, by); x.stroke();
      }
      x.fillStyle = 'rgba(255,255,255,.7)'; x.font = '600 15px Lexend, Arial, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
      [0, 15, 30, 45].forEach(a => { const [lx, ly] = toXY(a * DEG, R1 + 15); x.fillText(String(a), lx, ly); });
      // the needle line
      const ok = deg >= band[0] && deg <= band[1];
      const [nx, ny] = toXY(deg * DEG, R1 + 4), [mx, my] = toXY(deg * DEG, R0);
      x.strokeStyle = ok ? '#2ff0de' : '#f3c35a'; x.lineWidth = 4; x.lineCap = 'round';
      x.beginPath(); x.moveTo(mx, my); x.lineTo(nx, ny); x.stroke();
      x.font = '700 26px Lexend, Arial, sans-serif'; x.fillStyle = ok ? '#2ff0de' : '#f3c35a';
      const [vx, vy] = toXY(Math.min(deg + 9, 60) * DEG, R1 * 0.62); x.fillText(`${Math.round(deg)}°`, vx, vy);
      tx.needsUpdate = true;
    };
    // origin at the entry point; X forward along the skin (the texture opens back toward the hub), Y along the skin normal
    const m4 = new THREE.Matrix4();
    api.place = (point, fwd, up) => {
      const z = V3().crossVectors(fwd, up).normalize();
      m4.makeBasis(fwd, up, z);
      mesh.quaternion.setFromRotationMatrix(m4);
      mesh.position.copy(point).addScaledVector(up, 0.0002);
    };
    return api;
  }

  /* ═════════════════════════ vein model ═════════════════════════ */
  function makeVeins(d) {
    const map = d.map && Array.isArray(d.map.veins) && d.map.veins.length ? d.map : { veins: [{ y: 0.3, bend: 0.04, width: 0.75, depth: 3.6 }, { y: 0.55, bend: 0.01, width: 1.12, depth: 3.0 }, { y: 0.76, bend: -0.05, width: 0.68, depth: 4.6 }], best: 2, spot: 0.5 };
    const raw = map.veins;
    // Lua sends a 1-based index; the browser demo data a 0-based one: the wider of the two candidates
    const b1 = clamp((+map.best || 1) - 1, 0, raw.length - 1), b2 = clamp(+map.best || 0, 0, raw.length - 1);
    const best = (+raw[b2].width || 0) > (+raw[b1].width || 0) ? b2 : b1;
    const veins = raw.slice(0, 3).map((v, i) => {
      const width = clamp(+v.width || 0.8, 0.4, 1.4), depth = clamp(+v.depth || 3.5, 1.5, 7);
      const y0 = clamp(+v.y || 0.5, 0.1, 0.9), bend = clamp(+v.bend || 0, -0.2, 0.2);
      const Py = [y0 + bend * 0.6, y0 - bend, y0 + bend, y0 - bend * 0.5];
      const yAt = u => { const w = 1 - u; return w * w * w * Py[0] + 3 * w * w * u * Py[1] + 3 * w * u * u * Py[2] + u * u * u * Py[3]; };
      const vis = clamp(1.25 - depth / 6, 0.35, 1);
      const R = rngOf(hashStr(`vein:${i}:${v.seed || 0}:${y0}:${width}`));
      // a vein shows over part of the forearm and dives under elsewhere; the best one runs the whole way
      const isBest = i === best;
      const ua = isBest ? 0.0 : 0.02 + R() * 0.22, ub = isBest ? 1.0 : 0.98 - R() * 0.22;
      const p1 = R() * TAU, p2 = R() * TAU, p3 = R() * TAU;
      // gentle meander (m) and how much it stands out along its length
      const wig = u => 0.0009 * Math.sin(u * 15 + p1) + 0.0005 * Math.sin(u * 37 + p2);
      const show = u => smooth(ua, ua + 0.07, u) * smooth(ub, ub - 0.07, u) * (0.62 + 0.38 * (0.5 + 0.5 * Math.sin(u * 8.5 + p3)));
      const o = {
        i, width, depth, vis, best: isBest, ua, ub, show,
        rv: (0.95 + 0.62 * width) * MM,              // lumen radius, full
        dv: (1.3 + depth * 0.5) * MM,                 // centre depth under the skin
        ridge: (0.16 + 0.24 * width) * vis * MM,      // raised height, full
        rb: (2.6 + 0.8 * width) * MM,                 // ridge (bump) radius: wide and soft, a vein not a crease
        at: u => [lerp(V0, V1, u), (yAt(clamp(u, 0, 1)) - 0.5) * T_SPAN + wig(clamp(u, 0, 1))],
        bumps: [],
      };
      return o;
    });
    // bump chains: one soft ridge per vein where it shows (≤ 216 bumps in all, the engine keeps 256)
    let total = 0;
    veins.forEach(v => { v.len = (v.ub - v.ua) * (V1 - V0) * 1.01; total += v.len / (v.rb * 1.05); });
    const scaleN = Math.min(1, 216 / Math.max(1, total));
    veins.forEach(v => {
      const n = Math.max(8, Math.floor(v.len / (v.rb * 1.05) * scaleN));
      for (let k = 0; k <= n; k++) {
        const u = lerp(v.ua, v.ub, k / n), p = v.at(u);
        v.bumps.push({ u, s: p[0], t: p[1], r: v.rb, h: v.ridge * v.show(u), k: 1, b: null });
      }
    });
    return { veins, best: veins[best] || veins[0], spot: clamp(+map.spot || 0.5, 0.05, 0.95) };
  }
  // nearest point of a vein's centre line to (s, t): { u, d (m), s, t, dir [ds, dt] }
  function nearest(v, s, t) {
    let u = clamp((s - V0) / (V1 - V0), 0, 1);
    for (let it = 0; it < 3; it++) {
      const p = v.at(u), q = v.at(u + 0.002), ds = q[0] - p[0], dt = q[1] - p[1], L2 = ds * ds + dt * dt || 1e-9;
      u = clamp(u + ((s - p[0]) * ds + (t - p[1]) * dt) / L2 * 0.002, 0, 1);
    }
    const p = v.at(u), q = v.at(Math.min(1, u + 0.004)), r = v.at(Math.max(0, u - 0.004));
    const dx = q[0] - r[0], dy = q[1] - r[1], l = Math.hypot(dx, dy) || 1;
    return { u, d: Math.hypot(s - p[0], t - p[1]), s: p[0], t: p[1], dir: [dx / l, dy / l] };
  }
  function nearestVein(s, t) {
    let best = null;
    for (const v of G.veins) { const n = nearest(v, s, t); if (!best || n.d < best.n.d) best = { v, n }; }
    return best;
  }
  const blownAt = (v, s) => G.blows.some(b => b.v === v && Math.abs(b.s - s) < 0.016);

  /* ═════════════════════════ boot / teardown ═════════════════════════ */
  function boot(d) {
    const FS = X.S;
    injectCss();
    const host = X.ui.host;
    const name = d.name || '';
    const tone = d.tone !== undefined && d.tone !== null && d.tone !== '' ? clamp(+d.tone, 0, 1) : TONES[hashStr(name || 'patient') % TONES.length];
    const sex = d.sex === 'f' ? 'f' : 'm';
    const seed = (hashStr(`${name}:${d.site || ''}`) % 99991) + 1;
    const stage = document.createElement('div');
    stage.className = 'fiv-stage';
    host.prepend(stage);
    host.classList.add('fiv-on');
    const vm = makeVeins(d);
    const focusUv = [(WORK.s / ARM_W) + 0.5, 0.5];
    let S;
    try {
      S = NZA3D.createScene(stage, {
        tone, sex, seed, region: d.site || 'r_lower_arm', size: [ARM_W, ARM_H], quality: 'medium',   // the in-game cap: preview = game
        focus: { uv: focusUv, size: [0.23, 0.075], view: 0.3 }, work: [WORK.w, WORK.h],
      });
    } catch (e) { stage.remove(); host.classList.remove('fiv-on'); throw e; }
    const bin = [];
    const keep = o => { if (o) bin.push(o); return o; };
    const gauge = clamp(Math.round(+d.gauge || 18), 14, 26);
    S.__gauge = gauge;
    const g = G = {
      S, d, stage, alive: true, t: 0, uiT: 0, tone, sex,
      band: Array.isArray(d.angle) && d.angle.length >= 2 ? [+d.angle[0], +d.angle[1]] : [15, 30],
      maxAtt: Math.max(1, Math.round(+d.attempts || 2)), gauge,
      fillTime: Math.max(0.5, +d.tourniquetFill || 3), flashT: clamp(+d.flash || 0.9, 0.3, 3),
      veins: vm.veins, bestVein: vm.best, spot: vm.spot,
      ph: 'tq', sub: '', lmb: false, mx: innerWidth / 2, my: innerHeight / 2, moved: false,
      fill: 0, fillVis: 0, bumpT: 0, bumpDirty: true,
      tq: { on: false, prog: 0, slack: 1, release: 0 },
      palp: { on: false, press: 0, bounce: 0, at: null, dimple: null, near: null },
      mark: null, swab: { cov: 0, done: false, t: 0 },
      nd: null, adv: 0, wd: 0, wdFly: -1, cap: { on: false, prog: 0, done: false },
      dress: { D: null, rub: false, cover: 0, settledT: 0, warnT: 0 },
      blows: [], jobs: [], cur: { p: null, h: null }, keepBin: bin, wideKey: '', textKey: '',
    };
    // vein bumps
    g.veins.forEach(v => v.bumps.forEach(b => { b.b = S.bumps.add({ uv: S.stToUv(b.s, b.t), radius: b.r, height: 0.000001 }); }));
    // props (the skin clip plane starts out of the way: nothing is cut until the needle goes in)
    g.clip = new THREE.Plane(V3(0, 1, 0), 1);    // catheter
    g.clipN = new THREE.Plane(V3(0, 1, 0), 1);   // needle (off again once it leaves for the sharps bin)
    g.clipWas = S.renderer.localClippingEnabled;
    S.renderer.localClippingEnabled = true;
    const M = g.M = materials(S, gauge, keep, g.clip, g.clipN);
    g.hand = buildHand(S, M, keep);
    g.swabT = buildSwab(S, M, keep);
    g.capT = buildCap(S, M, keep);
    g.can = buildCannula(S, M, keep);
    g.tqm = buildTourniquet(S, M, keep);
    g.tint = buildVeinTint(S, g.veins, tone, keep);
    g.prot = buildGauge(S, keep);
    const clothY = S._cloth ? S._cloth.position.y : -S.shape.R * 1.55;
    g.bin = buildSharps(S, M, keep, V3(0.088, clothY, -0.13));
    g.tqm.set(0.001, S.shape.R + 0.006);
    // cursor ring (unzoomed layer, like the suture close-up)
    const cur = document.createElement('div');
    cur.className = 'fiv-cur';
    cur.innerHTML = '<svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span>';
    (document.getElementById('nza-layer-anchors') || document.body).appendChild(cur);
    g.curEl = cur; g.curFg = cur.querySelector('.fg'); g.curSvg = cur.querySelector('svg'); g.curTx = cur.querySelector('.tx');
    // the field app forwards right-drag / wheel to the game camera: not while the close-up owns them
    const app = NZA.apps.field;
    g.camInput = app ? app.camInput : undefined;
    if (app) app.camInput = false;
    // the wheel sets the needle angle while aiming (capture: before the engine's zoom on the canvas)
    g.onWheel = e => {
      if (!G || G !== g || g.ph !== 'insert' || !g.nd || g.nd.st !== 'aim') return;
      e.preventDefault(); e.stopPropagation();
      setAngle(g.nd.deg - Math.sign(e.deltaY) * 2);
    };
    stage.addEventListener('wheel', g.onWheel, { capture: true, passive: false });
    g.onMove = e => { g.mx = e.clientX; g.my = e.clientY; g.moved = true; };
    window.addEventListener('mousemove', g.onMove, true);
    // compile every material now (no hitch on first use)
    [g.hand.group, g.swabT.group, g.capT.group, g.can.group, g.tqm.group, g.prot.mesh].forEach(o => { o.visible = true; });
    try { S.prewarm([], true); S.renderer.compile(S.scene, S.camera); } catch (e) { /* compiles on first draw */ }
    [g.hand.group, g.swabT.group, g.capT.group, g.can.group, g.prot.mesh].forEach(o => { o.visible = false; });
    S.layers.decay('wet', 0);
    S.on('frame', (dt, render) => frame(dt, render));
    S.on('down', e => down(e));
    S.on('up', e => up(e));
    S.on('pointer', e => { g.mx = e.clientX; g.my = e.clientY; g.moved = true; });
    S.start();
    return g;
  }

  function teardown() {
    const g = G;
    G = null;
    if (!g) return;
    g.alive = false;
    clearTimeout(g.timer);
    try { g.stage.removeEventListener('wheel', g.onWheel, { capture: true }); } catch (e) { /* gone */ }
    window.removeEventListener('mousemove', g.onMove, true);
    if (g.S) { try { g.S.renderer.localClippingEnabled = !!g.clipWas; } catch (e) { /* gone */ } }
    if (g.S) { try { g.S.dispose(); } catch (e) { console.error('[field iv3d] dispose', e); } }
    g.keepBin.forEach(o => { try { o.dispose(); } catch (e) { /* freed with the scene */ } });
    if (g.curEl) g.curEl.remove();
    if (g.tipEl) g.tipEl.remove();
    if (g.stage) g.stage.remove();
    if (X && X.ui.host) X.ui.host.classList.remove('fiv-on');
    const app = NZA.apps.field;
    if (app) app.camInput = g.camInput;
  }

  /* ═════════════════════════ HUD ═════════════════════════ */
  const STEP_IDS = ['tq', 'find', 'insert', 'advance', 'withdraw', 'secure'];
  const STEP_EN = { tq: 'Tourniquet on', find: 'Find and clean a vein', insert: 'Needle in', advance: 'Slide the cannula', withdraw: 'Needle out and cap', secure: 'Dress the site' };
  const stepNames = () => STEP_IDS.map(id => T(`t_${id}`, STEP_EN[id]));
  const keyCap = code => (X ? X.keyName(code) : code);
  const insertKey = () => (X.S.keys && X.S.keys.insert) || 'Space';
  const advKey = () => (X.S.keys && X.S.keys.advance) || 'KeyE';
  const held = code => !!(X.S.held && X.S.held[code]);

  function hints() {
    const g = G, aim = g && g.ph === 'insert';
    const h = aim ? [{ keys: [T('k_wheel', 'Wheel')], label: T('h_angle', 'Angle') }, { keys: ['↑', '↓'], label: T('h_angle', 'Angle') }]
      : [{ keys: [T('k_wheel', 'Wheel')], label: T('h_zoom', 'Zoom') }];
    h.push({ keys: [T('k_rmb', 'RMB')], label: T('h_look', 'Look around') }, { keys: ['R'], label: T('h_recentre', 'Recentre') });
    return h;
  }
  function toolList() {
    const g = G, ph = g.ph, sub = g.sub;
    const st = (active, done, locked) => (active ? 'active' : done ? 'done' : locked ? 'locked' : '');
    const releasing = g.tq.on && (ph === 'advance' || ph === 'withdraw' || ph === 'secure');
    const notYet = T('tool_not_yet', 'Not yet — follow the step on the left.');
    return [
      { key: '1', icon: 'clamp', label: releasing ? T2('iv_tool_tq_off', 'Release tourniquet') : T2('iv_tool_tq', 'Tourniquet'),
        sub: g.tq.on && !releasing ? T2('iv_tq_on_short', 'On') : T('tool_tq_sub', 'Upper arm'),
        state: ph === 'tq' || releasing ? 'active' : (g.tq.on || ['withdraw', 'secure'].includes(ph)) ? 'done' : '' },
      { key: '2', icon: 'target', label: T('tool_fingers', 'Fingers'), sub: T('tool_fingers_sub', 'Feel the vein'), state: st(ph === 'find' && sub === 'palp', !!g.mark, ph === 'tq'), why: notYet },
      { key: '3', icon: 'gauze', label: T('tool_swab', 'Alcohol swab'), sub: T('tool_swab_sub', '70% alcohol'), state: st(ph === 'find' && sub === 'swab', g.swab.done && ph !== 'find', !g.mark), why: T('swab_why', 'Mark a vein first.') },
      { key: '4', icon: 'needle', label: T2('iv_tool_cannula', 'Cannula {g}G', { g: g.gauge }), sub: T('tool_cannula_sub', 'Over the needle'),
        state: st(ph === 'insert' || ph === 'advance' || (ph === 'withdraw' && sub === 'needle'), (ph === 'withdraw' && sub === 'cap') || ph === 'secure', !['insert', 'advance', 'withdraw', 'secure'].includes(ph)), why: notYet },
      { key: '5', icon: 'plus', label: T('tool_cap', 'Cap'), sub: T('tool_cap_sub', 'Luer bung'), state: st(ph === 'withdraw' && sub === 'cap', g.cap.done, !(ph === 'withdraw' && sub === 'cap') && !g.cap.done), why: T('cap_why', 'The needle has to come out first.') },
      { key: '6', icon: 'bandage', label: T('tool_dressing', 'Clear dressing'), sub: T('tool_dressing_sub', 'Film'), state: st(ph === 'secure', X.S.iv && X.S.iv.secured, ph !== 'secure'), why: T('dress_why', 'Cap the hub first.') },
    ];
  }
  function stats() {
    const g = G, iv = X.S.iv;
    return [
      { id: 'site', label: T2('st_site', 'Site'), value: g.d.siteLabel || T2('site_forearm', 'Forearm'), small: true },
      { id: 'att', label: T2('st_attempts', 'Attempts'), value: `${iv.attempts}/${g.maxAtt}`, tone: iv.attempts > 1 ? 'amber' : '' },
      { id: 'g', label: T2('st_cannula', 'Cannula'), value: `${g.gauge}G` },
    ];
  }
  function stepText() {
    const g = G, ph = g.ph, sub = g.sub, a = g.band;
    if (ph === 'tq') return T('s_tq', 'Hold {LMB} on the **upper arm** ring until the band is tight (or press {1}). The veins below it fill up.');
    if (ph === 'find') {
      if (g.fill < 0.999) return T2('iv_fill', 'Veins filling… {p}%', { p: Math.round(g.fill * 100) });
      if (sub === 'palp') return T('s_palp', 'Hold {LMB} on the forearm to feel for a vein. A good one is **springy** — let go on it to mark it.');
      if (sub === 'swab') return T('s_swab', 'Hold {LMB} and scrub the marked spot with the **alcohol swab** until the ring is full.');
      return T('s_dry', 'Clean. Let the alcohol dry — hands off for a moment.');
    }
    if (ph === 'insert') {
      if (g.nd && (g.nd.st === 'blown' || g.nd.st === 'gone')) return X.S.iv.attempts >= g.maxAtt ? T('s_blown_last', 'Through the back wall — and that was the last attempt.') : T('s_blown', 'Through the back wall. The cannula comes out; then a fresh one on another spot.');
      if (g.nd && g.nd.inVein) return T2('iv_flash', 'Blood in the chamber — stop there.');
      return T('s_insert', 'Set **{a}–{b}°** with the wheel (or ↑ ↓), then hold {LMB} on the mark. Let go as soon as blood shows in the chamber.', { a: a[0], b: a[1] });
    }
    if (ph === 'advance') return T('s_advance', 'Hold {LMB} (or {{key}}) to slide the cannula off the needle into the vein. {p}%', { key: keyCap(advKey()), p: Math.round(g.adv * 100) });
    if (ph === 'withdraw') {
      if (sub === 'cap') return T('s_cap', 'Hold {LMB} on the open hub to screw the **cap** on.');
      if (g.tq.on) return T('s_tqoff', 'Release the **tourniquet** first — click the band (or press {1}).');
      return T('s_needle', 'Hold {LMB} on the hub (or drag it back) to draw the needle out into the sharps bin. {p}%', { p: Math.round(g.wd * 100) });
    }
    if (ph === 'secure') {
      const D = g.dress.D;
      if (X.S.iv.secured) return T2('iv_done', 'Line in and running.');
      if (D && (D.state === 'placed' || D.state === 'falling')) return T('s_rub', 'Hold {LMB} and smooth the film down until it sticks. {p}%', { p: Math.round(D.stuck * 100) });
      return T('s_dress', 'Lift the clear dressing by its **border**, lay it over the hub and the entry point, then let go.');
    }
    return '';
  }
  function tipText() {
    const g = G, ph = g.ph, sub = g.sub;
    if (ph === 'tq') return [T('tip_tq', 'Tight enough to stop the veins draining, not the artery: the hand stays pink.'), ''];
    if (ph === 'find' && sub === 'palp' && g.fill >= 0.999) return [T('tip_palp', 'Look for a **straight**, wide vein. Press and let go: it should bounce back.'), ''];
    if (ph === 'find' && sub === 'swab') return [T('tip_swab', 'Scrub from the middle outward. Do not touch the spot again once it is clean.'), ''];
    if (ph === 'insert' && g.nd && (g.nd.st === 'blown' || g.nd.st === 'gone')) return [T('tip_blown', 'Blood leaks into the tissue: a bruise and a firm swelling. Pick a fresh part of a vein, flatter and slower.'), 'red'];
    if (ph === 'insert') return [T('tip_insert', 'Bevel up, along the vein. Too steep and you go straight through the back wall.'), 'amber'];
    if (ph === 'advance') return [T('tip_advance', 'Keep the needle still — only the soft cannula moves forward.'), ''];
    if (ph === 'withdraw' && sub !== 'cap' && g.tq.on) return [T('tip_tqoff', 'With the band still on, the vein empties out through the open hub.'), 'red'];
    if (ph === 'withdraw' && sub !== 'cap') return [T('tip_needle', 'The needle goes straight into the sharps bin — never back into the cannula.'), ''];
    if (ph === 'secure') return [T('tip_dress', 'The film must cover the entry point so you can still see it later.'), ''];
    return ['', ''];
  }
  function panel(full) {
    const g = G, pp = X.ui.pp;
    if (!g || !pp) return;
    const text = stepText();
    if (text !== g.textKey) { g.textKey = text; pp.set({ text }); }
    pp.set({ stats: stats() });
    let w;
    const iv = X.S.iv;
    if (g.ph === 'tq') w = { label: T('w_tight', 'Band'), value: String(Math.round(g.tq.prog * 100)), unit: '%', tone: g.tq.on ? 'teal' : '', meter: { value: g.tq.prog, zone: [0.95, 1] }, caption: T('w_tight_cap', 'Hold on the upper arm') };
    else if (g.ph === 'find' && g.fill < 0.999) w = { label: T('w_fill', 'Veins'), value: String(Math.round(g.fill * 100)), unit: '%', meter: { value: g.fill }, caption: T('w_fill_cap', 'Filling under the band') };
    else if (g.ph === 'find' && g.sub === 'palp') {
      const b = g.palp.on ? g.palp.bounce : g.mark ? iv.palpQ : 0;
      w = { label: T2('d_bounce', 'Rebound'), value: String(Math.round(b * 100)), unit: '%', tone: b > 0.7 ? 'teal' : b > 0.35 ? 'amber' : '', meter: { value: b, zone: [0.7, 1] },
        caption: b > 0.7 ? T2('b_good', 'Springy') : b > 0.35 ? T2('b_ok', 'Soft') : T('w_palp_cap', 'Press on a vein'), captionTone: b > 0.7 ? 'teal' : b > 0.35 ? 'amber' : '' };
    } else if (g.ph === 'find') w = { label: T('w_clean', 'Clean'), value: String(Math.round(g.swab.cov * 100)), unit: '%', tone: g.swab.done ? 'teal' : '', meter: { value: g.swab.cov, zone: [0.85, 1] }, caption: g.swab.done ? T('w_dry', 'Drying') : T('w_clean_cap', 'Scrub inside the ring') };
    else if (g.ph === 'insert' && g.nd && (g.nd.st === 'blown' || g.nd.st === 'gone')) {
      w = { label: T2('st_angle', 'Angle'), value: String(Math.round(g.nd.deg)), unit: '°', tone: 'red', meter: { value: g.nd.deg / 45, zone: [g.band[0] / 45, g.band[1] / 45], tone: 'red' },
        caption: T('w_blown', 'Vein blown'), captionTone: 'red' };
    } else if (g.ph === 'insert') {
      const a = g.nd ? g.nd.deg : 0, off = a < g.band[0] || a > g.band[1];
      const depth = g.nd && g.nd.L > 0 ? T('w_depth', 'Needle {d} mm in', { d: (g.nd.L).toFixed(1) }) : T2('cap_angle', 'Enter at {a}–{b}°', { a: g.band[0], b: g.band[1] });
      w = { label: T2('st_angle', 'Angle'), value: String(Math.round(a)), unit: '°', tone: off ? 'amber' : 'teal', meter: { value: a / 45, zone: [g.band[0] / 45, g.band[1] / 45], tone: off ? 'amber' : '' },
        caption: g.nd && g.nd.inVein ? T2('d_flash', 'Blood') : depth, captionTone: g.nd && g.nd.inVein ? 'teal' : off ? 'amber' : '' };
    } else if (g.ph === 'advance') w = { label: T2('d_cannula', 'Cannula'), value: String(Math.round(g.adv * 100)), unit: '%', tone: g.adv >= 1 ? 'teal' : '', meter: { value: g.adv }, caption: T('w_adv_cap', 'Off the needle, into the vein') };
    else if (g.ph === 'withdraw' && g.sub === 'cap') w = { label: T('w_cap', 'Cap'), value: String(Math.round(g.cap.prog * 100)), unit: '%', meter: { value: g.cap.prog }, caption: T('w_cap_cap', 'Screw it onto the hub') };
    else if (g.ph === 'withdraw') w = { label: T('w_needle', 'Needle'), value: String(Math.round(g.wd * 100)), unit: '%', tone: g.tq.on ? 'red' : '', meter: { value: g.wd, tone: g.tq.on ? 'red' : '' }, caption: g.tq.on ? T('w_tq_on', 'Tourniquet still on') : T('w_needle_cap', 'Out into the sharps bin'), captionTone: g.tq.on ? 'red' : '' };
    else if (g.ph === 'secure') { const D = g.dress.D, s = D ? D.stuck : 0; w = { label: T('w_seal', 'Seal'), value: String(Math.round(s * 100)), unit: '%', tone: s >= 0.9 ? 'teal' : '', meter: { value: s, zone: [0.9, 1] }, caption: T('w_seal_cap', 'Film over the hub and the entry'), captionTone: '' }; }
    if (w) { const k = JSON.stringify(w); if (k !== g.wideKey) { g.wideKey = k; pp.set({ wide: w }); } }
    const tp = tipText();
    if (g.tipEl && (full || g.tipEl.dataset.k !== tp.join('|'))) {
      g.tipEl.dataset.k = tp.join('|');
      g.tipEl.className = `fiv-tip ${tp[1]}`;
      g.tipEl.innerHTML = tp[0] ? `<span>${NZA.rich(tp[0])}</span>` : '';
    }
  }
  const refreshTools = () => { if (G && X.ui.pp) X.ui.pp.set({ tools: toolList() }); };
  const flash = (type, text, ms) => { if (X.ui.pp) X.ui.pp.flash(type, text, ms); };
  function mountTip() {
    const g = G, pp = X.ui.pp;
    if (!pp) return;
    if (g.tipEl && g.tipEl.isConnected) return;
    const body = pp.el.querySelector('.pp-body');
    const after = body && body.querySelector('.pp-text');
    g.tipEl = document.createElement('div');
    g.tipEl.className = 'fiv-tip';
    if (after && after.nextSibling) body.insertBefore(g.tipEl, after.nextSibling); else if (body) body.appendChild(g.tipEl);
  }

  /* cursor ring: progress (0..1) and / or a short label next to the pointer */
  // stamped on the sim clock: a label lives while its tick keeps setting it (any frame rate, and a
  // frozen preview still keeps only what was live when it froze)
  const curP = (p, text, tone) => { G.cur.p = { p, text, tone, t: G.t }; };
  const curH = (text, tone) => { G.cur.h = { text, tone, t: G.t }; };
  function updateCursor() {
    const g = G, el = g.curEl;
    const t = g.t;
    const cp = g.cur.p && t - g.cur.p.t < 0.25 ? g.cur.p : null, ch = g.cur.h && t - g.cur.h.t < 0.25 ? g.cur.h : null;
    const on = !!(cp || ch) && g.moved;
    el.classList.toggle('on', on);
    if (!on) return;
    el.style.transform = `translate(${g.mx.toFixed(1)}px,${g.my.toFixed(1)}px)`;
    const p = cp ? clamp(cp.p, 0, 1) : 0;
    g.curFg.setAttribute('stroke-dasharray', `${(p * 119.4).toFixed(1)} 120`);
    g.curSvg.style.display = cp ? '' : 'none';
    el.classList.toggle('red', !!(cp && cp.tone === 'red'));
    el.classList.toggle('amber', !!(cp && cp.tone === 'amber'));
    const tx = (ch && ch.text) || (cp && cp.text) || '';
    const te = g.curTx;
    if (te.textContent !== tx) te.textContent = tx;
    te.className = `tx ${(ch && ch.tone) || (cp && cp.tone) || ''}`;
  }

  /* ═════════════════════════ steps ═════════════════════════ */
  function view(name) {
    const g = G, S = g.S, iv = X.S.iv;
    const st = (s, t) => S.stToUv(s, t);
    let v;
    if (name === 'tq') v = { uv: st(0.085, 0.004), w: 0.3, pitch: 1.1 };
    else if (name === 'find') v = { uv: st(-0.012, 0.006), w: 0.26, pitch: 1.14 };
    else if (name === 'insert' || name === 'advance') { const m = g.mark || { s: -0.01, t: 0 }; v = { uv: st(m.s - 0.004, m.t + 0.003), w: 0.13, pitch: 0.92 }; }
    else if (name === 'tqoff') { const m = g.mark || { s: -0.01, t: 0 }; v = { uv: st((m.s + S_TQ) / 2, m.t * 0.5), w: 0.3, pitch: 1.08 }; }
    else if (name === 'needle') { const m = g.mark || { s: -0.01, t: 0 }; v = { uv: st(m.s - 0.012, m.t - 0.006), w: 0.19, pitch: 1.0 }; }
    else if (name === 'secure') { const E = (g.nd && g.nd.E) || [g.mark ? g.mark.s : -0.01, g.mark ? g.mark.t : 0]; v = { uv: st(E[0] - 0.036, E[1] + 0.002), w: 0.2, pitch: 1.12 }; }
    if (!v) return;
    S.controls.frame(v.uv, v.w, { pitch: v.pitch, yaw: 0, instant: false });
    void iv;
  }
  function useTool(id) {
    const g = G, S = g.S;
    S.tools.press(false);
    S.tools.follow = true;
    const t = id === 'hand' ? g.hand : id === 'swab' ? g.swabT : id === 'cap' ? g.capT : null;
    // one glove: it holds the swab, or presses on its own
    const inner = g.hand.inner;
    if (id === 'swab' && inner.parent !== g.swabT.group) { g.swabT.group.add(inner); inner.position.copy(g.swabT.lift); }
    if (id !== 'swab' && inner.parent !== g.hand.group) { g.hand.group.add(inner); inner.position.set(0, 0, 0); }
    S.tools.use(t);
    g.tool = id || null;
  }
  function go(ph, sub) {
    const g = G, iv = X.S.iv;
    g.ph = ph; g.sub = sub || '';
    iv.phase = ph;
    X.S.n = STEP_IDS.indexOf(ph) + 1;
    const pp = X.ui.pp;
    if (pp) pp.set({ step: X.S.n, total: 6, title: T(`t_${ph}`, STEP_EN[ph]), titleTone: '', tag: T2('t_iv', 'IV cannulation'), steps: stepNames(), hints: hints() });
    mountTip();
    const S = g.S;
    S.markers.clear();
    g.prot.mesh.visible = false;
    if (ph === 'tq') {
      useTool(null);
      S.markers.set('tq', { uv: S.stToUv(S_TQ, -0.004), kind: 'ring', size: 0.03, pulse: true });
      view('tq');
    } else if (ph === 'find') {
      if (g.sub === 'palp' || !g.sub) { g.sub = 'palp'; useTool('hand'); }
      if (g.sub === 'swab') { useTool('swab'); markSwab(); }
      if (g.mark && g.sub !== 'palp') S.markers.set('mark', { uv: S.stToUv(g.mark.s, g.mark.t), kind: 'pin', size: 0.006, lift: 0.006 });
      view('find');
    } else if (ph === 'insert') {
      useTool(null);
      startAim();
      view('insert');
    } else if (ph === 'advance') {
      useTool(null);
      view('advance');
    } else if (ph === 'withdraw') {
      useTool(null);
      if (g.sub === 'cap') { useTool('cap'); S.markers.set('hub', { uv: hubUv(), kind: 'ring', size: 0.014, pulse: true }); view('needle'); }
      else { g.sub = 'needle'; if (g.tq.on) { S.markers.set('tq', { uv: S.stToUv(S_TQ, g.tqm.aB * S.shape.R), kind: 'pin', size: 0.012, lift: 0.046 }); view('tqoff'); } else { S.markers.set('hub', { uv: hubUv(), kind: 'ring', size: 0.014, pulse: true }); view('needle'); } }
    } else if (ph === 'secure') {
      useTool(null);
      flattenVeins();
      startDressing();
      view('secure');
    }
    g.textKey = '';
    refreshTools();
    panel(true);
  }

  /* ── 1 · tourniquet ── */
  function tqTick(dt) {
    const g = G, tq = g.tq, R = g.S.shape.R;
    if (!tq.on && g.ph === 'tq') {
      const pressing = g.lmb && g.press && g.press.what === 'tq';
      if (pressing) { tq.prog = Math.min(1, tq.prog + dt / 1.0); curP(tq.prog, T('cur_tight', 'Tightening…')); }
      else if (!tq.auto) tq.prog = Math.max(0, tq.prog - dt * 1.6);
      if (tq.auto) tq.prog = Math.min(1, tq.prog + dt / 0.45);
      const e = smooth(0, 1, tq.prog);
      g.tqm.group.visible = tq.prog > 0.01;
      g.tqm.set(lerp(0.5, TAU + 0.5, smooth(0, 0.75, tq.prog)), R + lerp(0.006, 0.0003, smooth(0.6, 1, tq.prog)));
      void e;
      if (tq.prog >= 1) applyTq();
      return;
    }
    if (tq.release > 0) {
      // the buckle pops: the strap slackens and lies loose round the arm
      tq.release = Math.min(1, tq.release + dt / 0.5);
      g.tqm.set(TAU + 0.5, R + lerp(0.0003, 0.0055, smooth(0, 1, tq.release)));
    }
  }
  function applyTq() {
    const g = G, iv = X.S.iv;
    if (g.tq.on) return;
    g.tq.on = true; g.tq.prog = 1; g.tq.auto = false;
    g.tqm.group.visible = true;
    g.tqm.set(TAU + 0.5, g.S.shape.R + 0.0003);
    iv.tq = true; iv.fill = 0;
    X.post('ivTq', { on: true });
    snd('click', 500);
    flash('ok', T2('iv_tq_on', 'Tourniquet on. Veins filling…'));
    g.S.controls.shake(0.15, 200);
    go('find', 'palp');
  }
  function releaseTq() {
    const g = G, iv = X.S.iv;
    if (!g.tq.on) return;
    g.tq.on = false; g.tq.release = 0.001;
    iv.tq = false;
    X.post('ivTq', { on: false });
    snd('click', 400);
    flash('ok', T2('iv_tq_off', 'Tourniquet off.'));
    if (g.ph === 'withdraw' && g.sub === 'needle') { g.S.markers.remove('tq'); g.S.markers.set('hub', { uv: hubUv(), kind: 'ring', size: 0.014, pulse: true }); view('needle'); }
    g.textKey = '';
    refreshTools();
    panel(true);
  }

  /* veins: fill under the band, relax after it, flatten under the fingers, collapse when blown */
  function veinTick(dt) {
    const g = G, iv = X.S.iv;
    const target = g.tq.on ? 1 : (g.ph === 'tq' ? 0 : 0.35);
    const rate = g.tq.on ? 1 / g.fillTime : 1 / 2.2;
    if (g.fill < target) g.fill = Math.min(target, g.fill + dt * rate);
    else if (g.fill > target) g.fill = Math.max(target, g.fill - dt * rate);
    iv.fill = g.tq.on ? g.fill : iv.fill;
    if (g.ph === 'find' && g.fill >= 0.999 && g.sub === '') g.sub = 'palp';
    // visual fill eases in (a vein swells, it does not jump)
    const vis = smooth(0, 1, g.fill);
    g.bumpT -= dt;
    const changed = Math.abs(vis - g.fillVis) > 0.004;
    if ((changed || g.bumpDirty) && g.bumpT <= 0) {
      g.fillVis = vis;
      g.bumpT = 1 / 14;
      g.bumpDirty = false;
      const pr = g.palp;
      for (const v of g.veins) for (const b of v.bumps) {
        let k = vis;
        // the fingers squash the vein under them
        if (pr.on && pr.at) { const d = Math.hypot(b.s - pr.at[0], b.t - pr.at[1]); k *= 1 - 0.85 * pr.press * (1 - smooth(0.004, 0.011, d)); }
        // a blown segment collapses into the bruise
        for (const bl of g.blows) if (bl.v === v) k *= lerp(1, 0.25, 1 - smooth(0.006, 0.02, Math.abs(b.s - bl.s)));
        const h = b.h * k;
        if (b.b && Math.abs(h - (b.cur || 0)) > 0.000004) { b.cur = h; b.b.set({ height: Math.max(0.000001, h) }); }
      }
    }
    const amt = smooth(0.05, 1, g.fill) * lerp(0.9, 0.45, g.tone);
    g.tint.set(g.fillVis, amt);
  }

  // the band is off and the veins have gone down: their last tenth of a millimetre of relief goes, so the
  // film's skin collision (every bump, every film vertex) stays cheap. The tint stays.
  function flattenVeins() {
    const g = G;
    if (g.flat || g.tq.on) return;
    g.flat = true;
    for (const v of g.veins) for (const b of v.bumps) { if (b.b) { b.b.remove(); b.b = null; } }
  }

  /* ── 2 · palpate, mark, swab ── */
  function bounceAt(s, t) {
    const g = G;
    const nv = nearestVein(s, t);
    if (!nv) return { q: 0, nv };
    const v = nv.v, n = nv.n;
    if (blownAt(v, n.s)) return { q: 0, nv, blown: true };
    const dn = n.d / (v.rv + 1.1 * MM);
    let q = Math.exp(-(dn * dn) / 1.6) * (0.55 + v.width * 0.4) * (0.4 + 0.6 * v.vis);
    const spotS = lerp(V0, V1, g.spot);
    const straight = v.best ? Math.exp(-((n.s - spotS) ** 2) / (2 * 0.048 * 0.048)) : 0.35;
    q *= 0.55 + 0.45 * straight;
    q *= smooth(0.5, 1, g.fill);
    return { q: clamp(q, 0, 1), nv };
  }
  function palpTick(dt) {
    const g = G, S = g.S, pr = g.palp, hit = g.hit;
    if (g.fill < 0.999) { if (g.lmb && hit) curH(T2('iv_fill', 'Veins filling… {p}%', { p: Math.round(g.fill * 100) }), 'amber'); return; }
    if (pr.on && hit) {
      pr.press = Math.min(1, pr.press + dt * 5);
      pr.at = [hit.s, hit.t];
      const b = bounceAt(hit.s, hit.t);
      pr.bounce = lerp(pr.bounce, b.q, 1 - Math.exp(-dt * 12));
      pr.near = b.nv;
      pr.blown = b.blown;
      g.bumpDirty = true;
      if (!pr.dimple) pr.dimple = S.bumps.add({ uv: hit.uv, radius: 0.0075, height: -0.000001 });
      pr.dimple.set({ uv: hit.uv, height: -0.00055 * pr.press });
      const tone = pr.bounce > 0.7 ? '' : pr.bounce > 0.35 ? 'amber' : 'red';
      curP(pr.bounce, pr.blown ? T('cur_blown', 'Blown here') : pr.bounce > 0.7 ? T2('b_good', 'Springy') : pr.bounce > 0.35 ? T2('b_ok', 'Soft') : T2('b_none', 'Nothing'), tone);
      pr.tickT = (pr.tickT || 0) - dt;
      if (pr.bounce > 0.7 && pr.tickT <= 0) { pr.tickT = 0.5; snd('tick'); }
    } else if (pr.dimple) {
      pr.press = Math.max(0, pr.press - dt * 6);
      pr.dimple.set({ height: -0.00055 * pr.press });
      if (pr.press <= 0) { pr.dimple.remove(); pr.dimple = null; }
      g.bumpDirty = true;
    }
  }
  function palpUp() {
    const g = G, S = g.S, pr = g.palp, iv = X.S.iv;
    if (!pr.on) return;
    pr.on = false;
    S.tools.press(false);
    if (g.fill < 0.999) return;
    if (pr.blown) { flash('warn', T('blown_here', 'That part of the vein is blown — feel further along.')); return; }
    if (!pr.at || pr.bounce < 0.35 || !pr.near) { flash('warn', T2('iv_nothing', 'Nothing there. Feel further along the forearm.')); return; }
    // the mark goes on the middle of the vein the fingers found
    const v = pr.near.v, n = nearest(v, pr.at[0], pr.at[1]);
    g.mark = { s: n.s, t: n.t, v, dir: n.dir };
    iv.mark = { x: (n.s - V0) / (V1 - V0) * 300, y: (n.t / T_SPAN + 0.5) * 150 };
    iv.palpQ = pr.bounce; iv.vein = { width: v.width, depth: v.depth };
    S.markers.set('mark', { uv: S.stToUv(n.s, n.t), kind: 'pin', size: 0.006, lift: 0.006 });
    flash(pr.bounce > 0.7 ? 'ok' : 'warn', pr.bounce > 0.7 ? T2('iv_marked_good', 'Vein marked — firm and springy.') : T2('iv_marked_soft', 'Marked — small and soft. Harder to hit.'));
    snd('click', 820);
    later(g, 0.65, () => { if (G === g && g.ph === 'find' && g.sub === 'palp') { g.sub = 'swab'; useTool('swab'); markSwab(); g.textKey = ''; refreshTools(); panel(true); } });
  }
  function markSwab() {
    const g = G, S = g.S;
    if (!g.mark) return;
    // a fresh scrub: no leftover wetness, and nothing dries while scrubbing (after a blown vein the
    // last site was left drying — that decay would eat the new scrub)
    if (!g.swab.done && !g.swab.cov) { S.layers.clear('wet'); S.layers.decay('wet', 0); }
    S.markers.set('swab', { uv: S.stToUv(g.mark.s, g.mark.t), kind: 'dashed', size: SWAB_R * 2.3, pulse: false, opacity: 0.85 });
    S.markers.set('mark', { uv: S.stToUv(g.mark.s, g.mark.t), kind: 'pin', size: 0.006, lift: 0.006 });
  }
  function swabTick(dt) {
    const g = G, S = g.S, sw = g.swab, hit = g.hit;
    if (sw.done) {
      sw.t += dt;
      if (sw.t > 1.1 && g.sub === 'dry') { g.sub = ''; go('insert'); }
      return;
    }
    const muv = S.stToUv(g.mark.s, g.mark.t);
    if (g.lmb && hit) {
      // the pad scrubs: a wet film where it rubs (stronger in the middle of the pad)
      S.layers.paint('wet', hit.uv, 0.0075, 1.5 * dt, { hardness: 0.35 });
      S.layers.paint('wet', hit.uv, 0.011, 0.5 * dt, { hardness: 0.1 });
      sw.rubT = (sw.rubT || 0) + dt;
      sw.measT = (sw.measT || 0) - dt;
      if (sw.measT <= 0) { sw.measT = 0.1; sw.cov = S.layers.coverage('wet', muv, SWAB_R, 0.28); }
      curP(sw.cov, T('cur_scrub', 'Scrubbing'));
      if (sw.cov >= 0.85) {
        sw.done = true; sw.t = 0; g.sub = 'dry';
        S.tools.press(false);
        useTool(null);
        S.layers.decay('wet', 0.42);
        S.markers.remove('swab');
        flash('ok', T('swab_done', 'Clean — let it dry.'));
        snd('success');
        g.textKey = ''; refreshTools(); panel(true);
      }
    }
  }

  /* ── 3 · needle in ── */
  // the skin plane at the entry point cuts away whatever of the device is under the skin
  function setClip(plane, on) {
    const g = G, S = g.S, nd = g.nd;
    if (!on || !nd || !nd.E) { plane.set(V3(0, 1, 0), 1); return; }
    const P = V3(), N = V3();
    S._surf(nd.E[0], nd.E[1], P, N);
    P.addScaledVector(N, S.heightAt(S.stToUv(nd.E[0], nd.E[1])) - 0.0001);
    plane.setFromNormalAndCoplanarPoint(N, P);
  }
  function startAim() {
    const g = G, iv = X.S.iv;
    g.nd = { st: 'aim', deg: g.nd && g.nd.deg ? g.nd.deg : 34, L: 0, E: null, f: [1, 0], tent: 0, inVein: false, wasIn: false, inT: 0, flash: 0, hold: 0, retract: 0, v: null, lat: 0 };
    iv.angle = g.nd.deg; iv.tip = 0; iv.inVein = false; iv.inT = 0; iv.blown = false; iv.flash = 0; iv.cannula = 0; iv.withdraw = 0;
    g.adv = 0; g.wd = 0; g.wdFly = -1; g.advDone = false; g.wdDone = false; g.handOn = false;
    g.can.group.visible = false;
    g.can.needleG.position.set(0, 0, 0); g.can.cathG.position.set(0, 0, 0);
    g.can.needleG.rotation.set(0, 0, 0);
    g.can.needleG.visible = true;
    g.can.blood.scale.y = 0.001;
    setClip(g.clip, false); setClip(g.clipN, false);
    // dots along the vein ahead of the mark: the direction to aim
    const S = g.S, m = g.mark;
    if (m) {
      S.markers.set('mark', { uv: S.stToUv(m.s, m.t), kind: 'ring', size: 0.0045, pulse: true });
      for (let k = 1; k <= 5; k++) {
        const n = nearest(m.v, m.s + k * 0.0042, m.t);
        S.markers.set(`dot${k}`, { uv: S.stToUv(n.s, n.t), kind: 'dot', size: 0.0016, pulse: false, opacity: 0.55 - k * 0.07 });
      }
    }
  }
  function setAngle(a) {
    const g = G;
    if (!g || g.ph !== 'insert' || !g.nd || g.nd.st !== 'aim') return;
    const v = clamp(Math.round(a), 5, 50);
    if (v === g.nd.deg) return;
    g.nd.deg = v;
    X.S.iv.angle = v;
    snd('tick');
  }
  // world frame of the cannula from an entry point (s, t), a direction along the skin and an angle
  const _P = V3(), _N = V3(), _Ts = V3(), _Tt = V3();
  function devFrame(s, t, f, deg) {
    const S = G.S;
    const sp = S._surfaceAtST ? S._surfaceAtST(s, t, {}) : S.surfaceAt(S.stToUv(s, t));
    S._surf(s, t, _P, _N);
    S._tangents(s, t, _Ts, _Tt);
    const n = _N.clone();
    const fw = _Ts.clone().multiplyScalar(f[0]).addScaledVector(_Tt, f[1]).normalize();
    const a = deg * DEG;
    const d = fw.clone().multiplyScalar(Math.cos(a)).addScaledVector(n, -Math.sin(a)).normalize();   // into the skin
    const Y = d.clone().negate();
    const Z = n.clone().addScaledVector(Y, -n.dot(Y)).normalize();
    const Xa = V3().crossVectors(Y, Z).normalize();
    return { point: sp.point.clone(), n, fw, d, X: Xa, Y, Z };
  }
  const _m4 = new THREE.Matrix4();
  function poseCannula(fr, tipPos) {
    const grp = G.can.group;
    _m4.makeBasis(fr.X, fr.Y, fr.Z);
    grp.quaternion.setFromRotationMatrix(_m4);
    grp.position.copy(tipPos);
    grp.visible = true;
    grp.updateMatrixWorld(true);   // sub-steps / previews read it before the next render
  }
  function vInMm(v) {
    const g = G, mid = ((g.band[0] + g.band[1]) / 2) * DEG;
    return clamp((2 * v.rv / MM) / (Math.sin(mid) * g.flashT), 3, 16);
  }
  function insertTick(dt) {
    const g = G, S = g.S, nd = g.nd, hit = g.hit, iv = X.S.iv;
    if (!nd) return;
    const holding = g.lmb || held(insertKey());
    if (nd.st === 'aim') {
      if (!hit) { g.can.group.visible = false; g.prot.mesh.visible = false; return; }
      // aim along the vein under the pointer
      const nv = nearestVein(hit.s, hit.t);
      let f = [1, 0];
      if (nv && nv.n.d < 0.012) f = nv.n.dir[0] >= 0 ? nv.n.dir : [-nv.n.dir[0], -nv.n.dir[1]];
      nd.f = [lerp(nd.f[0], f[0], 0.35), lerp(nd.f[1], f[1], 0.35)];
      const fr = devFrame(hit.s, hit.t, nd.f, nd.deg);
      poseCannula(fr, fr.point.clone().addScaledVector(fr.d, -0.0035));
      g.prot.mesh.visible = true;
      g.prot.draw(nd.deg, g.band);
      g.prot.place(fr.point, fr.fw, fr.n);
      const on = nv && nv.n.d < nv.v.rv * 0.85;
      if (!g.lmb) curH(on ? T('cur_on_vein', 'On the vein') : T('cur_off_vein', 'Off the vein'), on ? 'teal' : 'amber');
      // a press that began here (not a button still held from the step before), or the insert key
      const start = (g.lmb && g.press && g.press.ph === 'insert') || held(insertKey());
      if (start) {
        nd.st = 'tent'; nd.tent = 0; nd.E = [hit.s, hit.t]; nd.fr = fr; nd.L = 0;
        nd.v = nv ? nv.v : null;
        if (!iv.angleUsed.length) iv.angleUsed.push(nd.deg);
        nd.dimple = S.bumps.add({ uv: S.stToUv(hit.s, hit.t), radius: 0.003, height: -0.000001 });
        setClip(g.clip, true); setClip(g.clipN, true);
      }
      return;
    }
    const fr = nd.fr;
    g.prot.mesh.visible = nd.st === 'tent' || nd.st === 'in';
    if (nd.st === 'tent') {
      // the tip presses the skin in before it gives
      nd.tent = Math.min(1, nd.tent + dt / 0.14);
      nd.dimple.set({ height: -0.00045 * nd.tent });
      poseCannula(fr, fr.point.clone().addScaledVector(fr.d, lerp(-0.0035, 0.00035, nd.tent)));
      curP(0.02, T('cur_in', 'Going in…'));
      if (nd.tent >= 1) {
        nd.st = 'in'; nd.L = 0.35;
        S.layers.paint('blood', S.stToUv(nd.E[0], nd.E[1]), 0.0005, 0.45, { hardness: 0.6 });
        snd('tone', 240, 40, { vol: 0.03, type: 'triangle' });
      }
      return;
    }
    if (nd.st === 'in') {
      nd.dimple.set({ height: -0.00018 });
      const v = nd.v;
      const vIn = v ? vInMm(v) : 8, vOut = vIn * 1.6;
      if (holding && !nd.done) nd.L += dt * (nd.inVein ? vIn : vOut);
      // where is the tip? along the skin by L cos, under it by L sin
      const a = nd.deg * DEG, Lm = nd.L * MM;
      const ts = nd.E[0] + nd.f[0] * Lm * Math.cos(a), tt = nd.E[1] + nd.f[1] * Lm * Math.cos(a), depth = Lm * Math.sin(a);
      poseCannula(fr, fr.point.clone().addScaledVector(fr.d, Lm));
      iv.tip = nd.L;
      let inside = false, lat = 99, rr = 0;
      if (v && !blownAt(v, ts)) {
        const n = nearest(v, ts, tt);
        const rv = v.rv * (0.55 + 0.45 * smooth(0, 1, g.fill));
        lat = n.d;
        if (lat < rv) { rr = Math.sqrt(rv * rv - lat * lat); inside = Math.abs(depth - v.dv) <= rr; }
        nd.lat = lat; nd.rv = rv;
        // through the back wall
        if (nd.wasIn && !inside && depth > v.dv) { blowVein(ts, tt); return; }
      }
      if (inside && !nd.inVein) {
        nd.inVein = true; nd.wasIn = true; iv.inVein = true;
        snd('beep', 1100, 60, 0.05);
        flash('ok', T2('iv_flash', 'Blood in the chamber — stop there.'), 1500);
        g.textKey = '';
      }
      if (nd.inVein) { nd.flash = Math.min(1, nd.flash + dt * 2.5); iv.flash = nd.flash; }
      g.can.blood.scale.y = Math.max(0.001, nd.flash);
      curP(clamp(nd.L / NEEDLE_LEN, 0, 1), nd.inVein ? T('cur_flash', 'Flashback — let go') : T('cur_in', 'Going in…'), nd.inVein ? '' : 'amber');
      // missed: beside the vein, or so flat it never got deep enough
      const maxL = NEEDLE_LEN * 0.78;
      const under = v ? depth > v.dv + (nd.rv || v.rv) + 0.0012 : depth > 0.008;
      if (!nd.inVein && (nd.L >= maxL || under)) {
        nd.st = 'retract'; nd.retract = 0;
        iv.misses += 1; X.S.iv.misses = iv.misses;
        const beside = !v || lat >= (nd.rv || v.rv);
        const shallow = v && depth < v.dv;
        flash('warn', beside ? T('miss_beside', 'Beside the vein — no blood. Back out and aim at the middle of it.') : shallow ? T2('iv_miss_flat', 'Too shallow — you passed over it. Back out and go steeper.') : T2('iv_miss_steep', 'Too steep — you passed under it. Back out and go flatter.'), 3200);
        snd('fail');
        return;
      }
      // let go with blood in the chamber → next step
      if (nd.inVein && !holding) {
        nd.inT += dt;
        if (nd.inT > 0.35) { nd.done = true; snd('success'); go('advance'); }
      } else nd.inT = 0;
      return;
    }
    if (nd.st === 'retract') {
      nd.retract = Math.min(1, nd.retract + dt / 0.5);
      const Lm = nd.L * MM * (1 - smooth(0, 1, nd.retract));
      poseCannula(fr, fr.point.clone().addScaledVector(fr.d, Lm - 0.003 * smooth(0.6, 1, nd.retract)));
      if (nd.retract >= 1) {
        if (nd.dimple) { nd.dimple.remove(); nd.dimple = null; }
        startAim();
        g.textKey = ''; refreshTools(); panel(true);
      }
    }
  }
  function blowVein(ts, tt) {
    const g = G, S = g.S, nd = g.nd, iv = X.S.iv;
    nd.st = 'blown'; iv.blown = true; iv.inVein = false;
    const v = nd.v;
    g.blows.push({ v, s: ts });
    g.bumpDirty = true;
    // blood leaks into the tissue: a spreading bruise and a firm swelling
    const uv = S.stToUv(ts, tt);
    S.layers.splat('bruise', uv, 0.006, 0.55, { seed: 31 + g.blows.length, count: 6 });
    S.layers.paint('bruise', uv, [0.011, 0.008], 0.28, { hardness: 0, grain: 0.3, grainScale: 90 });
    const hem = S.bumps.add({ uv, radius: 0.0001, height: 0.000001 });
    g.hems = g.hems || [];
    g.hems.push({ b: hem, t: 0 });
    S.layers.paint('blood', S.stToUv(nd.E[0], nd.E[1]), 0.0011, 0.6, { hardness: 0.4 });
    S.controls.shake(0.55, 420);
    snd('fail');
    flash('bad', T2('iv_blown', 'Through the back wall — that vein is gone.'), 0);
    if (!X.S.preview && g.d.responsive) NZA.speech({ name: g.d.name || '', text: T2('say_ouch', 'Ouch!'), ms: 1800 });
    // pull the needle out, then a new cannula (or the attempt is over)
    nd.blownT = 0;
  }
  function blownTick(dt) {
    const g = G, nd = g.nd;
    (g.hems || []).forEach(h => { if (h.t < 1) { h.t = Math.min(1, h.t + dt / 1.4); h.b.set({ radius: 0.009 * smooth(0, 1, h.t) + 0.0001, height: 0.0011 * smooth(0, 1, h.t) }); } });
    if (!nd || nd.st !== 'blown') return;
    nd.blownT += dt;
    const k = smooth(0.2, 0.9, nd.blownT);
    poseCannula(nd.fr, nd.fr.point.clone().addScaledVector(nd.fr.d, nd.L * MM * (1 - k) - 0.012 * smooth(0.7, 1.2, nd.blownT)));
    g.prot.mesh.visible = false;
    if (nd.blownT > 1.6) {
      nd.st = 'gone';
      if (nd.dimple) { nd.dimple.remove(); nd.dimple = null; }
      const iv = X.S.iv;
      if (iv.attempts >= g.maxAtt) { finish(true); return; }
      iv.attempts += 1; iv.blown = false; iv.flash = 0; iv.tip = 0; iv.inVein = false; iv.cannula = 0; iv.mark = null;
      g.mark = null; g.swab = { cov: 0, done: false, t: 0 };
      g.can.group.visible = false;
      g.palp.bounce = 0;
      S_clearWet();
      go('find', 'palp');
      flash('warn', T2('iv_new_site', 'New cannula — pick another spot.'));
    }
  }
  const S_clearWet = () => { try { G.S.layers.decay('wet', 0.6); } catch (e) { /* none */ } };

  /* ── 4 · advance the cannula ── */
  function advanceTick(dt) {
    const g = G, nd = g.nd, iv = X.S.iv;
    if (!nd || !nd.fr) return;
    const holding = g.lmb || held(advKey());
    if (holding && g.adv < 1) {
      g.adv = Math.min(1, g.adv + dt * 0.55);
      iv.cannula = g.adv;
      curP(g.adv, T('cur_slide', 'Sliding…'));
    }
    // the insert key on top pushes the needle on too (2D rule): through the back wall
    if (held(insertKey()) && nd.v) {
      nd.L += dt * vInMm(nd.v);
      const depth = nd.L * MM * Math.sin(nd.deg * DEG);
      if (depth > nd.v.dv + (nd.rv || nd.v.rv)) {
        blowVein(nd.E[0] + nd.f[0] * nd.L * MM, nd.E[1] + nd.f[1] * nd.L * MM);
        // back to step 3 on the HUD (not go(): that would start a new aim and drop the blown needle)
        g.ph = 'insert'; X.S.iv.phase = 'insert'; X.S.n = 3; g.can.cathG.position.y = 0;
        if (X.ui.pp) X.ui.pp.set({ step: 3, title: T('t_insert', STEP_EN.insert) });
        g.textKey = ''; refreshTools(); panel(true);
        return;
      }
    }
    // flatten the device as the cannula goes in
    const deg = lerp(nd.deg, LIE_DEG, smooth(0, 0.25, g.adv));
    const fr = devFrame(nd.E[0], nd.E[1], nd.f, deg);
    nd.frAdv = fr;
    poseCannula(fr, fr.point.clone().addScaledVector(fr.d, nd.L * MM));
    g.prot.mesh.visible = false;
    // the catheter slides forward over the needle until its hub reaches the skin
    const travel = Math.max(0, NEEDLE_LEN - HUB_OFF - nd.L) * MM;
    g.can.cathG.position.y = -travel * smooth(0, 1, g.adv);
    if (g.adv >= 1 && !g.advDone) {
      g.advDone = true;
      snd('success');
      flash('ok', T2('iv_cannula_in', 'Cannula home.'));
      later(g, 0.45, () => { if (G === g && g.ph === 'advance') go('withdraw', 'needle'); });
    }
  }
  function hubWorld() {
    const g = G;
    g.can.group.updateMatrixWorld(true);
    return g.can.cathG.localToWorld(V3(0, 41 * MM, 0));
  }
  function hubUv() {
    const g = G, nd = g.nd;
    if (!nd || !nd.E) return [0.5, 0.5];
    const S = g.S, back = 0.013;
    return S.stToUv(nd.E[0] - nd.f[0] * back, nd.E[1] - nd.f[1] * back);
  }

  /* ── 5 · tourniquet off, needle out, cap ── */
  function nearHub(hit, r) {
    if (!hit) return false;
    const h = hubWorld();
    return hit.point.distanceTo(h) < r;
  }
  function withdrawTick(dt) {
    const g = G, S = g.S, nd = g.nd, iv = X.S.iv;
    if (g.sub === 'needle') {
      if (g.wdFly >= 0) {
        // the needle flies into the sharps bin
        g.wdFly = Math.min(1, g.wdFly + dt / 0.6);
        const k = smooth(0, 1, g.wdFly), m = g.bin.mouth();
        const from = g.wdFrom, p = from.clone().lerp(m, k);
        p.y += Math.sin(k * Math.PI) * 0.05;
        const ng = g.can.needleG;
        g.can.group.updateMatrixWorld(true);
        const wpos = g.can.group.worldToLocal(p.clone());
        ng.position.copy(wpos).sub(V3(0, 60 * MM, 0));
        ng.rotation.x = -k * 1.2;
        if (g.wdFly >= 1) { ng.visible = false; g.wdFly = 2; }
        if (g.wdFly === 2 && !g.wdDone) {
          g.wdDone = true;
          later(g, 0.35, () => { if (G === g && g.ph === 'withdraw') { g.sub = 'cap'; go('withdraw', 'cap'); } });
        }
        return;
      }
      if (g.lmb && g.press && g.press.what === 'hub') {
        g.wd = Math.min(1, g.wd + dt * 0.62);
        // a drag back along the device pulls faster
        const p = g.press, dx = g.mx - (p.lx === undefined ? g.mx : p.lx), dy = g.my - (p.ly === undefined ? g.my : p.ly);
        p.lx = g.mx; p.ly = g.my;
        if (p.axis) { const along = -(dx * p.axis[0] + dy * p.axis[1]); if (along > 0) g.wd = Math.min(1, g.wd + along / Math.max(80, p.axisPx) * 1.6); }
        iv.withdraw = g.wd;
        curP(g.wd, T('cur_pull', 'Drawing back…'), g.tq.on ? 'red' : '');
        // a finger presses on the vein over the catheter tip (stops the backflow)
        if (!g.handOn) {
          g.handOn = true;
          const tipS = nd.E[0] + nd.f[0] * (NEEDLE_LEN - 8) * MM * Math.cos(LIE_DEG * DEG), tipT = nd.E[1] + nd.f[1] * (NEEDLE_LEN - 8) * MM;
          const sp = S.surfaceAt(S.stToUv(tipS, tipT));
          useTool('hand');
          S.tools.follow = false;
          S.tools.hit = { point: sp.point, normal: sp.normal, s: tipS, t: tipT, uv: S.stToUv(tipS, tipT) };
          // two fingertips on the vein just past the catheter tip: the hand lies low along the arm
          // from the elbow side (mostly off screen), never looming over the view
          Object.assign(g.hand.pose, { yaw: 0.06, tilt: 1.22 });
          g.hand.group.visible = true;
          S.tools.press(true);
        }
      }
      g.can.needleG.position.y = 48 * MM * smooth(0, 1, g.wd);
      if (g.wd >= 1) {
        g.can.group.updateMatrixWorld(true);
        g.wdFrom = g.can.needleG.localToWorld(V3(0, 60 * MM, 0));
        g.wdFly = 0;
        setClip(g.clipN, false);
        S.tools.press(false); useTool(null); Object.assign(g.hand.pose, { yaw: HAND_YAW, tilt: HAND_TILT }); g.handOn = false;
        if (g.tq.on) {
          iv.spill = true;
          const uv = hubUv();
          S.layers.splat('blood', uv, 0.006, 0.7, { seed: 7, count: 7 });
          S.fluids.drip(uv, 1.4);
          flash('bad', T2('iv_spill', 'Blood everywhere — the tourniquet was still on.'), 3200);
        } else { snd('success'); flash('ok', T2('iv_needle_out', 'Needle out and into the sharps bin.')); }
        S.markers.remove('hub');
      }
      return;
    }
    if (g.sub === 'cap') {
      const cp = g.cap;
      if (cp.on && !cp.done) {   // once done the cap lives in the hub's frame: hands off
        cp.prog = Math.min(1, cp.prog + dt / 0.75);
        curP(cp.prog, T('cur_cap', 'Screwing on…'));
        // from the hand to the hub, then a quarter-turn twist
        const k = smooth(0, 0.55, cp.prog);
        g.can.group.updateMatrixWorld(true);
        const hubBack = g.can.cathG.localToWorld(V3(0, 46.7 * MM + lerp(12, 0, k) * MM, 0));
        const cap = g.capT.group;
        cap.position.copy(cp.from).lerp(hubBack, k);
        const q = new THREE.Quaternion();
        g.can.group.getWorldQuaternion(q);
        cap.quaternion.copy(cp.fromQ).slerp(q, k);
        cap.rotateY(smooth(0.55, 1, cp.prog) * Math.PI * 0.6);
        if (cp.prog >= 1 && !cp.done) {
          cp.done = true; iv.flushed = true;
          // fix it to the hub (explicit local transform: no stale world matrix)
          g.can.cathG.add(cap);
          cap.position.set(0, 46.7 * MM, 0); cap.quaternion.identity(); cap.rotateY(Math.PI * 0.6);
          snd('click', 900);
          flash('ok', T('capped', 'Capped and closed.'));
          S.markers.remove('hub');
          later(g, 0.5, () => { if (G === g && g.ph === 'withdraw') go('secure'); });
        }
      }
    }
  }

  /* ── 6 · clear film dressing ── */
  // applied = the paper frame is peeled off: a thin reinforced edge stays, the write-on label too
  // canvas x → along the cannula (left = the hub's luer end, where the notch lets the line out),
  // canvas y → across the arm. applied = the paper frame is peeled off: a thin reinforced edge stays,
  // the write-on label too
  function filmCanvas(applied) {
    const w = 512, h = 512, c = cvs(w, h), x = c.getContext('2d');
    x.clearRect(0, 0, w, h);
    // clear window
    x.fillStyle = 'rgba(235,242,246,0.12)'; x.fillRect(0, 0, w, h);
    const b = applied ? 12 : 34;
    x.fillStyle = applied ? 'rgba(240,244,246,0.42)' : 'rgba(250,251,252,0.86)';
    x.fillRect(0, 0, w, b); x.fillRect(0, h - b, w, b); x.fillRect(0, 0, b, h); x.fillRect(w - b, 0, b, h);
    // notch for the line on the hub side
    x.clearRect(0, h / 2 - 40, b, 80);
    x.fillStyle = 'rgba(235,242,246,0.12)'; x.fillRect(0, h / 2 - 40, b, 80);
    // printed write-on label (generic), on the far border away from the hub
    const lx = applied ? w - 196 : w - b - 180, ly = applied ? 22 : b + 10;
    x.fillStyle = 'rgba(255,255,255,0.96)'; x.fillRect(lx, ly, 170, 70);
    x.strokeStyle = 'rgba(40,46,52,.65)'; x.lineWidth = 2; x.strokeRect(lx, ly, 170, 70);
    x.fillStyle = 'rgba(30,36,40,.85)'; x.font = '700 20px Lexend, Arial, sans-serif'; x.fillText('IV SITE', lx + 10, ly + 24);
    x.font = '500 15px Lexend, Arial, sans-serif'; x.fillText('DATE ____  TIME ____', lx + 10, ly + 52);
    // teal grip tab on the edge that leads toward the site
    if (!applied) { x.fillStyle = 'rgba(8,175,162,.85)'; x.fillRect(w - b, h * 0.3, b, h * 0.4); }
    return c;
  }
  const FILM = { w: 0.06, h: 0.058, ahead: 0.003 };   // size · film centre this far past the entry point (the notch meets the cap)
  // where the film goes: centre a little past the entry along the cannula, turned to it
  function filmGoal() {
    const g = G, E = g.nd.E, f = g.dress.dir;
    return [E[0] + f[0] * FILM.ahead, E[1] + f[1] * FILM.ahead];
  }
  // the point of the leading (tab) edge for a film centred at c
  const filmEdge = c => { const f = G.dress.dir, h = FILM.w / 2 - 0.0016; return [c[0] + f[0] * h, c[1] + f[1] * h]; };
  function startDressing() {
    const g = G, S = g.S, nd = g.nd;
    if (g.dress.D) return;
    const E = nd.E, l = Math.hypot(nd.f[0], nd.f[1]) || 1, f = [nd.f[0] / l, nd.f[1] / l];
    g.dress.dir = f;
    // out of its pack it rests on the forearm on the wrist side of the hub, a little toward the top
    // of the arm (clear of the panel), the tab edge toward the site
    const cs = E[0] - 0.074, ct = E[1] - 0.006;
    const D = S.dressing.create({ size: [FILM.w, FILM.h], pad: [-1, -1], uv: S.stToUv(cs, ct), angle: -Math.atan2(f[1], f[0]), curl: 0.6 });
    // a clear film: see-through window, frosted border
    const tx = new THREE.CanvasTexture(filmCanvas()); tx.encoding = THREE.sRGBEncoding; tx.anisotropy = 4;
    const mat = new THREE.MeshPhysicalMaterial({ map: tx, transparent: true, depthWrite: false, side: THREE.DoubleSide, roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.08, metalness: 0, envMapIntensity: 1.2 });
    g.keepBin.push(tx, mat);
    D.mesh.material = mat;
    D.mesh.castShadow = false;
    D.mesh.renderOrder = 4;
    g.dress.D = D;
    g.dress.rest = [cs, ct];
    g.dress.size = [FILM.w, FILM.h];
    g.dress.siteOn = true;
    S.markers.set('site', { uv: S.stToUv(...filmGoal()), kind: 'dashed', size: 0.034, pulse: true, opacity: 0.7 });
    buildTent();
  }
  // the film shrunk over the hub, the cap and the wings: the dressing engine's sheet only lies on the
  // skin, so where it crosses the device this tent takes over (fades in once the window covers the hub).
  // Built in the catheter's frame from the device's own profile, dilated into a taut membrane that
  // runs down to the skin, then fitted to the skin round its edge.
  function buildTent() {
    const g = G, S = g.S, cg = g.can.cathG;
    if (g.tent) return;
    g.can.group.updateMatrixWorld(true);
    // radius of the device along its axis (catheter frame, mm): catheter, hub, cap
    const hubP = [[18, 0.69], [33.4, 0.69], [33.5, 0.75], [34.1, 1.5], [35.4, 2.3], [36.8, 2.85], [38.2, 3.05], [46.1, 3.05], [46.3, 3.45], [47.3, 3.45], [47.5, 2.85], [53, 2.85], [53.2, 2.7], [55.1, 2.7], [55.6, 2.2], [55.7, 0.4]];
    const hubR = y => {
      if (y < hubP[0][0] || y > hubP[hubP.length - 1][0]) return 0;
      for (let i = 1; i < hubP.length; i++) if (y <= hubP[i][0]) { const a2 = hubP[i - 1], b2 = hubP[i]; return lerp(a2[1], b2[1], (y - a2[0]) / (b2[0] - a2[0])); }
      return 0;
    };
    const top = (x, y) => {   // highest point of the device at (x, y) (mm, catheter frame), or -9 where there is none
      let z = -9;
      const r = hubR(y);
      if (Math.abs(x) < r) z = Math.sqrt(r * r - x * x);
      if (Math.hypot(x, y - 40.6) < 2.2) z = Math.max(z, 7.1);                                    // injection port + its lid
      if (y > 36.4 && y < 43.4 && Math.abs(x) > 2 && Math.abs(x) < 9.5) z = Math.max(z, -1.3);   // wings
      return z;
    };
    const X0 = -13, X1 = 13, Y0 = 22, Y1 = 60, NX = 39, NY = 46, K = 1.25;   // K: slope of the taut film off the device
    const ex = new Float32Array(NX * NY), gx = i => lerp(X0, X1, i / (NX - 1)), gy = j => lerp(Y0, Y1, j / (NY - 1));
    for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) ex[j * NX + i] = top(gx(i), gy(j));
    const feat = [];
    for (let k = 0; k < ex.length; k++) if (ex[k] > -9) feat.push(k);
    const pos = new Float32Array(NX * NY * 3), col = new Float32Array(NX * NY * 4), uv = new Float32Array(NX * NY * 2);
    const P = V3(), Q = V3(), N = V3();
    for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) {
      const k = j * NX + i, x = gx(i), y = gy(j);
      let z = -9;
      for (const f of feat) { const zz = ex[f] - K * Math.hypot(x - gx(f % NX), y - gy(Math.floor(f / NX))); if (zz > z) z = zz; }
      // faint creases where the film is pulled down off the hub
      z += 0.07 * Math.sin(y * 2.3 + x * 0.4) * smooth(1, 3.5, Math.abs(x));
      P.copy(cg.localToWorld(Q.set(x * MM, y * MM, (z + 0.3) * MM)));
      // never below the flat film on the skin
      const q = S._toSurf(P), hs = S.heightAt(S.stToUv(q.s, q.t)) + 0.0007;
      const above = q.h - hs;
      if (above < 0) { S._surf(q.s, q.t, P, N); P.addScaledVector(N, hs); }
      pos[k * 3] = P.x; pos[k * 3 + 1] = P.y; pos[k * 3 + 2] = P.z;
      // where it lies on the skin the flat sheet already shows: the tent fades out there
      const a = smooth(0.0002, 0.0011, Math.max(0, above)) * smooth(0, 2.5, Math.min(i, NX - 1 - i, j, NY - 1 - j));
      col[k * 4] = col[k * 4 + 1] = col[k * 4 + 2] = 1; col[k * 4 + 3] = a;
      uv[k * 2] = i / (NX - 1); uv[k * 2 + 1] = j / (NY - 1);
    }
    const idx = [];
    for (let j = 0; j < NY - 1; j++) for (let i = 0; i < NX - 1; i++) { const a = j * NX + i, b2 = a + 1, c = a + NX, d = c + 1; idx.push(a, c, b2, b2, c, d); }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(col, 4));
    geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    g.keepBin.push(geo);
    // a faint haze (the film's own tint) + its reflections added on top: a clear film shows mostly as glints
    const haze = g.M.film;
    haze.vertexColors = true; haze.needsUpdate = true;
    const glint = new THREE.MeshPhysicalMaterial({ color: 0x000000, roughness: 0.14, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.05, specularIntensity: 1,
      envMapIntensity: 2.2, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending, vertexColors: true, side: THREE.FrontSide });
    g.keepBin.push(glint);
    const mesh = new THREE.Mesh(geo, haze), spec = new THREE.Mesh(geo, glint);
    mesh.renderOrder = 5; spec.renderOrder = 6; mesh.frustumCulled = spec.frustumCulled = false;
    S.scene.add(mesh, spec);
    g.tent = { mesh, spec, glint, k: 0 };
  }
  function tentTick(dt) {
    const g = G, t = g.tent, D = g.dress.D;
    if (!t) return;
    const on = !!D && D.state !== 'carried' && !g.dress.snap && g.dress.cover >= 1;
    t.k = clamp(t.k + (on ? dt / 0.6 : -dt / 0.25), 0, 1);
    const k = smooth(0, 1, t.k) * (0.75 + 0.25 * (D ? D.stuck : 0));
    g.M.film.opacity = 0.18 * k;
    t.glint.opacity = 1.3 * k;
    t.mesh.visible = t.spec.visible = t.k > 0.001;
  }
  function filmCovers() {
    // the entry point and the hub must lie under the clear window (not the border)
    const g = G, D = g.dress.D, S = g.S;
    if (!D) return 0;
    const pos = D.mesh.geometry.attributes.position, uv = D.mesh.geometry.attributes.uv;
    const pts = [S.surfaceAt(S.stToUv(g.nd.E[0], g.nd.E[1])).point, S.surfaceAt(hubUv()).point];
    let n = 0;
    for (const p of pts) {
      let best = 1e9, bi = -1;
      for (let i = 0; i < pos.count; i++) { const dx = pos.getX(i) - p.x, dy = pos.getY(i) - p.y, dz = pos.getZ(i) - p.z, d = dx * dx + dy * dy + dz * dz; if (d < best) { best = d; bi = i; } }
      const u = uv.getX(bi), v = uv.getY(bi);
      if (Math.sqrt(best) < 0.009 && u > 0.05 && u < 0.95 && v > 0.05 && v < 0.95) n++;
    }
    return n / pts.length;
  }
  function dressDown() {
    const g = G, S = g.S, D = g.dress.D;
    if (!D) return;
    const hit = g.hit;
    const pick = D.pick(hit);
    if (pick === 'edge' && D.stuck < 0.25 && D.state !== 'carried') {
      if (D.grab(hit)) { g.dress.cover = 0; g.stage.classList.add('grabbing'); snd('tone', 300, 40, { vol: 0.03, type: 'triangle' }); return; }
    }
    if (D.state === 'placed' || D.state === 'falling') { g.dress.rub = true; return; }
    if (pick === 'body') flash('warn', T('dress_edge', 'Pick it up by its **border**.'));
    void S;
  }
  function dressUp() {
    const g = G, S = g.S, D = g.dress.D;
    g.dress.rub = false;
    if (!D || D.state !== 'carried' || g.dress.snap) return;
    g.stage.classList.remove('grabbing');
    // let go close to the site: the hands lay it down square over it (a short glide, then it drops)
    const goal = S.surfaceAt(S.stToUv(...filmGoal())), c = D.center();
    const off = goal.point.clone().sub(c);
    off.addScaledVector(goal.normal, -off.dot(goal.normal));
    if (off.length() < 0.024) { g.dress.snap = { t: 0, from: D._target.clone(), to: D._target.clone().add(off), n: goal.normal.clone() }; return; }
    D.release(); g.dress.settledT = 0;
  }
  // the flat of the fingers smooths a palm-sized patch, not a point: the cursor and a ring round it
  function rubFilm(hit, dt) {
    const g = G, S = g.S, D = g.dress.D;
    D.rub(hit, dt);
    if (hit.s === undefined) return;
    for (let k = 0; k < 6; k++) {
      const a = k * Math.PI / 3 + g.t * 3, uv = S.stToUv(hit.s + Math.cos(a) * 0.011, hit.t + Math.sin(a) * 0.011);
      const sp = S.surfaceAt(uv);
      D.rub({ point: sp.point, normal: sp.normal }, dt * 0.8);
    }
  }
  // the frame comes off: a last firm sweep sticks every edge down (no corner left curling up)
  function pressAll() {
    const g = G, S = g.S, D = g.dress.D, f = g.dress.dir;
    const c = S._toSurf(D.center());
    for (let pass = 0; pass < 3; pass++) {
      for (let u = -0.034; u <= 0.0341; u += 0.0076) for (let v = -0.033; v <= 0.0331; v += 0.0076) {
        const sp = S.surfaceAt(S.stToUv(c.s + f[0] * u - f[1] * v, c.t + f[1] * u + f[0] * v));
        D.rub({ point: sp.point, normal: sp.normal }, 0.35);
      }
    }
  }
  function secureTick(dt) {
    const g = G, S = g.S, D = g.dress.D, dr = g.dress, iv = X.S.iv;
    if (!D || iv.secured) return;
    const hit = g.hit;
    const sn = dr.snap;
    if (sn) {
      sn.t = Math.min(1, sn.t + dt / 0.3);
      D.move({ point: sn.from.clone().lerp(sn.to, smooth(0, 1, sn.t)), normal: sn.n });
      if (sn.t >= 1) { dr.snap = null; D.release(); dr.settledT = 0; }
      return;
    }
    if (D.state === 'carried') { if (hit) D.move(hit); return; }
    if (!g.lmb) {
      const pick = hit ? D.pick(hit) : null;
      g.stage.classList.toggle('grab', pick === 'edge' && D.stuck < 0.25);
      if (pick === 'edge' && D.stuck < 0.25 && D.state === 'rest') curH(T('cur_grab', 'Grab the border'), 'teal');
    }
    if (D.state === 'placed' || D.state === 'falling') {
      dr.settledT += dt;
      dr.measT = (dr.measT || 0) - dt;
      if (dr.settledT > 0.4 && dr.measT <= 0) { dr.measT = 0.25; dr.cover = filmCovers(); }
    }
    // the target ring goes once the film lies over the site (back if it is lifted off again)
    const siteOn = !(dr.cover >= 1 && D.state !== 'carried');
    if (siteOn !== dr.siteOn) { dr.siteOn = siteOn; if (siteOn) S.markers.set('site', { uv: S.stToUv(...filmGoal()), kind: 'dashed', size: 0.034, pulse: true, opacity: 0.7 }); else S.markers.remove('site'); }
    if (dr.rub && g.lmb && hit && (D.state === 'placed' || D.state === 'falling')) { rubFilm(hit, dt); curP(D.stuck, T('cur_smooth', 'Smoothing')); }
    if (D.state === 'placed' && dr.settledT > 0.6 && dr.cover < 1 && D.stuck < 0.25) {
      dr.warnT -= dt;
      if (dr.warnT <= 0) { dr.warnT = 5; flash('warn', T('dress_cover', 'Cover the hub and the entry point — lift it by the border and try again.'), 3600); }
    }
    if (D.stuck >= 0.9 && dr.settledT > 0.4) {
      dr.cover = filmCovers();
      iv.secured = true;
      pressAll();
      // peel the paper frame off
      const m = D.mesh.material, old = m.map;
      m.map = new THREE.CanvasTexture(filmCanvas(true)); m.map.encoding = THREE.sRGBEncoding; m.map.anisotropy = 4; m.needsUpdate = true;
      g.keepBin.push(m.map);
      if (old) old.dispose();
      S.markers.clear();
      snd('click', 900);
      flash(dr.cover >= 1 ? 'ok' : 'warn', dr.cover >= 1 ? T2('iv_secured', 'Hub covered and taped.') : T('dress_part', 'Dressed — but the film does not cover everything.'));
      g.textKey = ''; refreshTools(); panel(true);
      later(g, 0.8, () => { if (G === g) finish(false); });
    }
  }

  /* ── result (same fields and scoring as the 2D panels) ── */
  function finish(failedRun) {
    const g = G, iv = X.S.iv;
    if (!g || g.finished) return;
    g.finished = true;
    g.S.tools.use(null);
    g.S.markers.clear();
    g.prot.mesh.visible = false;
    const band = g.band;
    const ang = iv.angleUsed[0] || iv.angle || 0;
    let score = 100 - (iv.attempts - 1) * 18 - iv.misses * 6 - (iv.spill ? 15 : 0) - (iv.flushed ? 0 : 6) - Math.round((1 - (iv.palpQ || 0)) * 25);
    if (ang < band[0] || ang > band[1]) score -= 10;
    if (g.dress.D && g.dress.cover < 1) score -= 6;
    if (failedRun) {
      if (X.ui.pp) X.ui.pp.set({ tools: [], title: T('t_failed', 'No line'), titleTone: 'bad', text: T('s_failed', 'Every attempt is used up — no line this time.') });
    } else if (X.ui.pp) X.ui.pp.set({ tools: [], text: T2('iv_done', 'Line in and running.') });
    X.sendResult('iv', { site: g.d.site, attempts: iv.attempts, angle: ang, secured: !!iv.secured, failed: !!failedRun, score: Math.round(clamp(failedRun ? 10 : score, 0, 100)) });
  }

  /* ═════════════════════════ input ═════════════════════════ */
  function down(e) {
    const g = G;
    if (!g || !g.alive || g.finished || e.button !== 0) return;
    g.lmb = true;
    if (e.clientX !== undefined) { g.mx = e.clientX; g.my = e.clientY; g.moved = true; }
    const S = g.S;
    const hit = g.hit = S.raycast();
    g.press = { what: '', ph: g.ph, sub: g.sub, x: g.mx, y: g.my };
    if (g.ph === 'tq') {
      if (hit && Math.abs(hit.s - S_TQ) < 0.05) { g.press.what = 'tq'; snd('tone', 300, 40, { vol: 0.03, type: 'triangle' }); }
      else flash('warn', T('tq_where', 'Hold on the **upper arm** — the ring by the elbow.'));
      return;
    }
    if (g.ph === 'find') {
      if (g.fill < 0.999) { flash('warn', T2('iv_fill', 'Veins filling… {p}%', { p: Math.round(g.fill * 100) }), 1400); return; }
      if (g.sub === 'palp') {
        if (!hit) return flash('warn', T('on_skin', 'Put your fingers on the forearm.'), 1500);
        g.palp.on = true; g.palp.bounce = 0; g.palp.press = 0;
        S.tools.press(true);
        return;
      }
      if (g.sub === 'swab') {
        if (!hit) return flash('warn', T('on_skin_swab', 'Put the swab on the forearm.'), 1500);
        S.tools.press(true);
        if (S.distanceUv(hit.uv, S.stToUv(g.mark.s, g.mark.t)) > 0.02) flash('warn', T('swab_where', 'Scrub inside the ring around the mark.'), 1800);
      }
      return;
    }
    if (g.ph === 'insert') {
      if (g.nd && g.nd.st === 'aim' && !hit) flash('warn', T('needle_where', 'Aim at the marked vein on the forearm.'), 1600);
      return;
    }
    if (g.ph === 'withdraw') {
      if (g.sub === 'needle') {
        if (g.tq.on && hit && Math.abs(hit.s - S_TQ) < 0.05) { releaseTq(); g.press.what = 'band'; return; }
        if (nearHub(hit, 0.03) || nearCan()) {
          g.press.what = 'hub';
          // screen direction of the device axis (toward the hub end): a drag that way pulls the needle
          const a = S.project(g.can.group.localToWorld(V3(0, 0, 0))), b = S.project(g.can.group.localToWorld(V3(0, 60 * MM, 0)));
          const dx = (b.x - a.x) * innerWidth, dy = (b.y - a.y) * innerHeight, l = Math.hypot(dx, dy) || 1;
          g.press.axis = [-dx / l, -dy / l]; g.press.axisPx = l;
          return;
        }
        flash('warn', g.tq.on ? T('tq_first', 'Release the **tourniquet** first (click the band or press {1}).') : T('hub_where', 'Hold on the **cannula hub**.'), 1800);
        return;
      }
      if (g.sub === 'cap') {
        const cp = g.cap;
        if (cp.on || cp.done) return;
        if (nearHub(hit, 0.025) || nearCan()) {
          cp.on = true; cp.prog = 0;
          const cap = g.capT.group;
          cp.from = cap.position.clone(); cp.fromQ = cap.quaternion.clone();
          S.tools.use(null); cap.visible = true; g.tool = null;
          return;
        }
        flash('warn', T('cap_where', 'Put the cap on the **open hub**.'), 1600);
        return;
      }
    }
    if (g.ph === 'secure') dressDown();
  }
  // the pointer is over the device itself (a screen-space test: the hub stands off the skin)
  function nearCan() {
    const g = G, S = g.S;
    if (!g.can.group.visible) return false;
    const p = S.project(hubWorld());
    return Math.hypot(p.x * innerWidth - g.mx, p.y * innerHeight - g.my) < 70 * (innerHeight / 1080);
  }
  function up(e) {
    const g = G;
    if (!g || e.button !== 0) return;
    g.lmb = false;
    if (g.ph === 'find' && g.sub === 'palp') palpUp();
    if (g.ph === 'find' && g.sub === 'swab') g.S.tools.press(false);
    if (g.ph === 'secure') dressUp();
    g.press = null;
  }

  // timers on the simulation clock (sub-stepped frames, demo sims): never the wall clock
  const later = (g, sec, fn) => { g.jobs.push({ at: g.t + sec, fn }); };
  function runJobs(g) {
    if (!g.jobs.length) return;
    const due = g.jobs.filter(j => g.t >= j.at);
    if (!due.length) return;
    g.jobs = g.jobs.filter(j => g.t < j.at);
    due.forEach(j => { if (G === g) j.fn(); });
  }

  /* ═════════════════════════ frame ═════════════════════════ */
  function frame(dt, render) {
    const g = G;
    if (!g || !g.alive) return;
    if (g.frozen) {   // preview stills: a held gesture stays on screen as it was
      if (render !== false) updateCursor();
      return;
    }
    g.t += dt;
    runJobs(g);
    if (G !== g) return;
    g.hit = g.S.raycast();
    veinTick(dt);
    tqTick(dt);
    blownTick(dt);
    if (!g.finished) {
      switch (g.ph) {
        case 'find': if (g.sub === 'palp') palpTick(dt); else swabTick(dt); break;
        case 'insert': insertTick(dt); break;
        case 'advance': advanceTick(dt); break;
        case 'withdraw': withdrawTick(dt); break;
        case 'secure': secureTick(dt); break;
        default: break;
      }
    }
    tentTick(dt);
    if (render !== false) {
      updateCursor();
      g.uiT -= dt;
      if (g.uiT <= 0) { g.uiT = 0.1; panel(); }
    }
  }

  /* ═════════════════════════ the handler app.js calls ═════════════════════════ */
  const H = {
    enter() {
      const FS = X.S, d = FS.data;
      teardown();
      FS.total = 6;
      d.siteLabel = d.siteLabel || X.L(`site_r_${d.site}`, d.site);
      FS.iv = { phase: 'tq', tq: false, fill: 0, attempts: 1, angle: 0, tip: 0, inVein: false, inT: 0, blown: false, flash: 0, mark: null, bounce: 0, palpQ: 0,
        cannula: 0, withdraw: 0, secured: false, flushed: false, spill: false, misses: 0, angleUsed: [], palp: false };
      X.clearMarks();
      try { boot(d); }
      catch (e) {
        console.error('[field iv3d] 3D view unavailable, using the 2D panels', e);
        failed = true; teardown();
        X.IV2D.enter();
        return;
      }
      go('tq');
    },
    go(ph) { if (G) go(ph); },
    tools() { refreshTools(); },
    text() { if (G) { G.textKey = ''; panel(true); } },
    tool(k) {
      const g = G;
      if (!g || g.finished) return;
      if (k === '1') {
        if (g.ph === 'tq' && !g.tq.on) { if (g.tq.prog < 1) { g.tq.auto = true; } return; }
        if (g.tq.on && (g.ph === 'advance' || g.ph === 'withdraw' || g.ph === 'secure')) { releaseTq(); return; }
        if (g.tq.on) flash('warn', T('tq_keep', 'Leave the tourniquet on until the cannula is in.'));
        return;
      }
      const t = toolList().find(x => x.key === k);
      if (!t) return;
      if (t.state === 'locked') { flash('warn', t.why || T('tool_not_yet', 'Not yet — follow the step on the left.'), 2200); return; }
      if (t.state === 'done') { flash('warn', T('tool_done', 'That part is done.'), 1600); return; }
    },
    key(e, isDown) {
      const g = G;
      if (!g) return false;
      if (isDown && g.ph === 'insert' && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) { setAngle(g.nd.deg + (e.key === 'ArrowUp' ? 1 : -1)); return true; }
      return false;
    },
    frame() { /* the 3D scene runs its own loop (S.on('frame')) */ },
    leave() { teardown(); },
    demo(stage) { demo(stage); },
  };

  /* ═════════════════════════ preview stages (sim, then run live) ═════════════════════════ */
  function demo(stage) {
    const g = G;
    if (!g) return false;
    const S = g.S;
    stage = String(stage || 'tq');
    S.stop();
    const sim = (sec, fn) => { const n = Math.ceil(sec * 30); for (let i = 0; i < n; i++) { if (fn) fn(i / n, i); S.step(1 / 30, false); } };
    const aimST = (s, t) => { const p = S.project(S.stToUv(s, t)); S.pointer.x = p.x; S.pointer.y = p.y; g.mx = p.x * innerWidth; g.my = p.y * innerHeight; g.moved = true; };
    const press = () => down({ button: 0 }), release = () => up({ button: 0 });
    // freeze = a still of a held gesture (the preview never lets go, so the live loop must not carry on)
    const done = freeze => { S.step(1 / 30, true); if (freeze) g.frozen = true; S.start(); return true; };
    sim(0.6);
    aimST(S_TQ, -0.004);
    if (stage === 'tq') return done();
    press(); sim(stage === 'tighten' ? 0.55 : 1.1);
    if (stage === 'tighten') return done(true);
    release();
    if (stage === 'fill') { aimST(-0.02, 0.01); sim(g.fillTime * 0.5); return done(true); }
    sim(g.fillTime + 0.3);
    const v = g.bestVein, sp = v.at(g.spot);
    // feel along the vein toward the spot
    aimST(sp[0] - 0.02, sp[1] + 0.006); sim(0.4); press();
    sim(0.6, f => aimST(lerp(sp[0] - 0.02, sp[0], f), lerp(sp[1] + 0.006, sp[1] + 0.0006, f)));
    if (stage === 'palpate') { sim(0.2); return done(true); }
    release(); sim(1.0);
    // scrub in circles
    const m = g.mark;
    aimST(m.s, m.t); sim(0.1); press();
    const scrub = sec => sim(sec, f => { const a = f * TAU * 5, r = 0.006 * (0.4 + 0.6 * Math.abs(Math.sin(f * 7))); aimST(m.s + Math.cos(a) * r, m.t + Math.sin(a) * r * 0.8); });
    if (stage === 'swab') { scrub(0.5); return done(true); }
    for (let k = 0; k < 8 && !g.swab.done; k++) scrub(0.8);
    release(); sim(1.4);
    // aim: the wheel brings the angle into the band
    aimST(m.s - 0.0025, m.t); sim(0.3);
    for (let k = 0; k < 10 && g.nd && g.nd.deg > (g.band[0] + g.band[1]) / 2 + 1; k++) setAngle(g.nd.deg - 2);
    sim(0.3);
    if (stage === 'insert') return done();
    if (stage === 'blown') {
      setAngle(44); sim(0.1); press();
      for (let k = 0; k < 120 && g.nd.st !== 'blown'; k++) sim(1 / 30);
      sim(0.7);
      return done(true);
    }
    press();
    for (let k = 0; k < 150 && !(g.nd.inVein && g.nd.flash > 0.5); k++) sim(1 / 30);
    if (stage === 'flash') { sim(0.15); return done(true); }
    release(); sim(0.6);
    // advance
    press(); sim(stage === 'advance' ? 0.9 : 2.2);
    if (stage === 'advance') return done(true);
    release(); sim(0.8);
    if (stage === 'tqoff') return done();
    // the band off, then the needle out
    aimST(S_TQ, -0.004); sim(0.1); press(); sim(0.05); release(); sim(0.9);
    const hp = S.project(hubWorld());
    S.pointer.x = hp.x; S.pointer.y = hp.y; g.mx = hp.x * innerWidth; g.my = hp.y * innerHeight;
    sim(0.1); press(); sim(stage === 'withdraw' ? 0.8 : 1.9);
    if (stage === 'withdraw') return done(true);
    release(); sim(1.4);
    if (stage === 'cap') { const p2 = S.project(hubWorld()); S.pointer.x = p2.x + 0.03; S.pointer.y = p2.y - 0.05; g.mx = S.pointer.x * innerWidth; g.my = S.pointer.y * innerHeight; sim(0.3); return done(); }
    const p3 = S.project(hubWorld());
    S.pointer.x = p3.x; S.pointer.y = p3.y; g.mx = p3.x * innerWidth; g.my = p3.y * innerHeight;
    sim(0.1); press(); sim(1.0); release(); sim(1.0);
    sim(0.6);
    const D = g.dress.D;
    if (!D) return done();
    const e0 = filmEdge(g.dress.rest), c0 = filmGoal(), e1 = filmEdge(c0);
    aimST(e0[0], e0[1]);
    if (stage === 'dress') return done();
    sim(0.05); press();
    sim(0.9, f => aimST(lerp(e0[0], e1[0], f), lerp(e0[1], e1[1], f)));
    if (stage === 'carry') { sim(0.1); return done(true); }
    release(); sim(1.4);
    if (stage === 'laid') return done();
    aimST(c0[0], c0[1]); sim(0.05); press();
    for (let k = 0; k < 14 && !X.S.iv.secured; k++) sim(1.5, f => aimST(c0[0] + Math.sin(f * TAU * 2 + k) * 0.026, c0[1] + Math.sin(f * TAU * 3 + k * 1.3) * (0.012 + 0.012 * (k % 3))));
    release(); sim(1.2);
    return done();
  }

  /* ═════════════════════════ export ═════════════════════════ */
  window.NZAFieldIV3D = {
    usable: () => !failed && !!(THREE && window.NZA3D && NZA3D.supported()),
    handler(ctx) { X = ctx; return H; },
    // test support (emulator scenarios): game state and screen positions of the things to click
    debug: {
      get g() { return G; },
      get iv() { return X && X.S.iv; },
      get last() { return X && X.S.lastResult; },
      screen(what) {
        const g = G;
        if (!g) return null;
        const S = g.S, px = p => ({ x: p.x * innerWidth, y: p.y * innerHeight });
        if (what === 'tq') return px(S.project(S.stToUv(S_TQ, -0.004)));
        if (what === 'spot') { const p = g.bestVein.at(g.spot); return px(S.project(S.stToUv(p[0], p[1]))); }
        if (what === 'mark' && g.mark) return px(S.project(S.stToUv(g.mark.s, g.mark.t)));
        if (what === 'aim' && g.mark) return px(S.project(S.stToUv(g.mark.s - 0.0025, g.mark.t)));
        if (what === 'hub' && g.can.group.visible) return px(S.project(hubWorld()));
        if (what === 'dressEdge' && g.dress.D) return px(S.project(S.stToUv(...filmEdge(g.dress.rest))));
        if (what === 'dressTarget' && g.dress.D) return px(S.project(S.stToUv(...filmEdge(filmGoal()))));
        if (what === 'site' && g.dress.D) return px(S.project(S.stToUv(...filmGoal())));
        if (what === 'uv') return (s, t) => px(S.project(S.stToUv(s, t)));
        return null;
      },
    },
  };
})();
