/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Bullet extraction (app 'bullet')          module: bullet
   Remove a bullet / shrapnel fragments in a draped surgical field, full-screen 3D close-up
   built on core/nza3d.js (skin, wounds, layers, fluids, stitches, dressing). Tools this app
   adds inside its own files: iodine swab stick, Yankauer suction, ring (bullet) forceps and the
   fragment meshes.

   Steps (NZA.ui.ProcPanel, checklist on the right):
     1 Locate        1 Probe      hold LMB in the wound: the probe follows the track — steer it with
                                  the mouse (resistance arrow) until it clicks on metal; on intact skin
                                  it palpates shallow fragments. X = read an X-ray film of the region
     2 Disinfect     2 Iodine     hold LMB and scrub outward from the site until the ring is 100 %
     3 Incise        3 Scalpel    Q / E blade depth, hold LMB and draw the cut over the fragment;
                                  start at an end to lengthen it. Too long / deep = blood loss
     4 Expose        4 Suction    hold Space to spread the edges, suction (4) / gauze (6) the blood
     5 Extract       5 Forceps    click the fragment to grip, draw the mouse back SLOWLY (grip /
                                  traction meters); A / D rock a lodged fragment; L leaves the rest
     6 Control bleed 6 Gauze      press on the bleeding point until the bleed is under the limit
     7 Suture        7 Suture kit near edge → pull across → release (same as the suture app)
     8 Dressing      8 Dressing   pick it up by an edge, lay it over, rub it down
   Then the result card (grade, eight parts, feedback) — Enter closes.

   Lua → JS   open { locale, cfg, patient{name,sex,bloodType,conscious,numb}, injury{id,type,region,
                     regionLabel,label,severity,bleed,retained,depth,contamination,pain},
                     fragments[{id,x,y,depth,size,shape,rot,lodge}], tone, hair, seed,
                     film{id,view,viewLabel,taken,quality,marked}|null, items{gauze},
                     location{kind,label}, bay, bloodWarn, vitals }
              vitals { hr, ecgRate, rhythm, spo2, sys, dia, map, rr, bloodPct, drip, infusing }
              result (server outcome)      abort (the server ended the session)
   JS → Lua   bullet:finish { result } → { ok, pending }     bullet:abort {}     bullet:exitBay {}
              bullet:flinch { pain }       bullet:close (core)
   Preview    index.html?app=bullet (&demo=shrapnel)   NZA.apps.bullet.demoTo('<stage>')
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const esc = NZA.esc, icon = NZA.icon, clamp = NZA.clamp;
  const MM = 0.001, TAU = Math.PI * 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  let LOC = {};
  const T = (k, fb, ...a) => { let s = LOC[k] !== undefined ? String(LOC[k]) : fb; a.forEach(v => { s = s.replace(/%[sd]/, String(v)); }); return s; };
  const pct = v => Math.round(clamp(v, 0, 1) * 100);
  const f1 = v => (Math.round((+v || 0) * 10) / 10).toFixed(1);
  const hash = s => { let h = 2166136261; s = String(s); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; };
  const rng = seed => { let a = seed >>> 0 || 1; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };

  // gameplay tuning; Config.Bullet.Game overrides (sent as data.cfg)
  const DEFAULTS = {
    quality: 'high',
    probeSpeed: 8, probeSlow: 0.3, trackRadius: 4.5, steerTol: 1.8, steerFail: 4.4, palpateDepth: 12, palpateTol: 3,
    prepRadius: 24, swabRadius: 4.4, swabReach: 320, redipTime: 0.6, prepDone: 0.97,
    bladeMin: 2, bladeMax: 16, bladeStart: 5, minCut: 8, coverTol: 4, maxPoints: 46, cutFast: 75,
    spreadTime: 1.5, tearAt: 1.15, exposeSpread: 0.7, exposeBlood: 0.42,
    grabTol: 2.4, pullSafe: 0.16, pullSlip: 0.36, pullDist: 0.24, gripLoss: 5, rocks: 3,
    bleedDone: 1.5, pressRate: 0.24, pressRadius: 10, poolRate: 0.006,
    gauzeRadius: 13, gauzeCapacity: 140, gauzeMax: 6, suctionRadius: 3.6,
    mmPerStitch: 8, minStitches: 2, maxStitches: 7, extraStitches: 2, bite: 4, biteMin: 1.2, biteMax: 9.5, minDrag: 0.3,
    stuckDone: 0.92, coverMin: 0.85,
    flinchPain: 40, flinchChance: 0.5,
    weights: { locate: 10, disinfect: 10, incise: 15, expose: 10, extract: 25, haemostasis: 10, suture: 12, dressing: 8 },
    fallbackTime: 18,
  };
  const STEPS = [
    { n: 1, id: 'locate', label: ['plan_1', 'Locate fragment'] },
    { n: 2, id: 'disinfect', label: ['plan_2', 'Disinfect site'] },
    { n: 3, id: 'incise', label: ['plan_3', 'Incise'] },
    { n: 4, id: 'expose', label: ['plan_4', 'Expose fragment'] },
    { n: 5, id: 'extract', label: ['plan_5', 'Extract projectile'] },
    { n: 6, id: 'control', label: ['plan_6', 'Control bleeding'] },
    { n: 7, id: 'suture', label: ['plan_7', 'Suture wound'] },
    { n: 8, id: 'dressing', label: ['plan_8', 'Apply dressing'] },
  ];
  const TOOLS = [
    { key: '1', id: 'probe', icon: 'probe', label: ['tool_probe', 'Probe'] },
    { key: '2', id: 'iodine', icon: 'drop', label: ['tool_iodine', 'Iodine swab'] },
    { key: '3', id: 'scalpel', icon: 'scalpel', label: ['tool_scalpel', 'Scalpel'] },
    { key: '4', id: 'suction', icon: 'wind', label: ['tool_suction', 'Suction'] },
    { key: '5', id: 'forceps', icon: 'forceps', label: ['tool_forceps', 'Forceps'] },
    { key: '6', id: 'gauze', icon: 'gauze', label: ['tool_gauze', 'Gauze'] },
    { key: '7', id: 'driver', icon: 'needle', label: ['tool_suture', 'Suture kit'] },
    { key: '8', id: 'dressing', icon: 'bandage', label: ['tool_dressing', 'Dressing'] },
    { key: 'X', id: 'xray', icon: 'xray', label: ['tool_xray', 'X-ray film'] },
  ];
  const MAIN = { 1: 'probe', 2: 'iodine', 3: 'scalpel', 4: 'suction', 5: 'forceps', 6: 'gauze', 7: 'driver', 8: 'dressing' };
  const ENGINE = { probe: 'probe', scalpel: 'scalpel', gauze: 'gauze', driver: 'needleDriver' };
  // subcutaneous fat (mm) per region: the blade should go through skin and fat, not into muscle
  const FAT = { head: 4, face: 4, neck: 6, chest: 10, back: 12, abdomen: 16, pelvis: 14, upper_arm: 7, lower_arm: 5, upper_leg: 11, lower_leg: 6 };
  const BONE = { head: 7, face: 9, neck: 34, chest: 46, back: 44, abdomen: 70, pelvis: 52, upper_arm: 30, lower_arm: 20, upper_leg: 44, lower_leg: 24 };
  const SAY = [['say_1', 'Argh! Careful!'], ['say_2', 'That hurts — what are you doing?!'], ['say_3', 'Easy… easy!'], ['say_4', 'I can feel that!'], ['say_5', 'Ahh… is it out yet?'], ['say_6', 'Please, stop for a second…']];

  const DEMO = {
    patient: { name: 'Michael Garcia', sex: 'm', bloodType: 'O-', conscious: true, numb: false },
    injury: { id: 'i3', type: 'gunshot', region: 'chest', regionLabel: 'Chest', label: 'Gunshot wound', severity: 3, bleed: 9.2, retained: 1, depth: 23, contamination: 34, pain: 62 },
    fragments: [{ id: 'f1', x: 6.5, y: -3.4, depth: 23, size: 10.5, shape: 'bullet', rot: 0.7, lodge: 0 }],
    tone: 0.3, seed: 4512,
    film: { id: 'A2034', view: 'chest', viewLabel: 'Chest', taken: '14/10 12:41', quality: 'sharp', marked: true },
    items: { gauze: 4 },
    location: { kind: 'bay', label: 'Ambulance · EMS 12' }, bay: true, bloodWarn: true,
    vitals: { hr: 88, ecgRate: 88, rhythm: 'sinus', spo2: 97, sys: 97, dia: 60, map: 72, rr: 18, bloodPct: 81, drip: 0, infusing: false },
  };
  const DEMO_SHRAPNEL = {
    patient: { name: 'Dana Whitfield', sex: 'f', bloodType: 'A+', conscious: true, numb: true },
    injury: { id: 'i5', type: 'shrapnel', region: 'l_upper_leg', regionLabel: 'Left thigh', label: 'Shrapnel wound', severity: 2, bleed: 5.4, retained: 3, depth: 14, contamination: 58, pain: 48 },
    fragments: [
      { id: 'f1', x: -4.2, y: 2.4, depth: 11, size: 5.5, shape: 'shard', rot: 2.1, lodge: 0 },
      { id: 'f2', x: 3.8, y: -1.6, depth: 15, size: 4.2, shape: 'shard', rot: 0.4, lodge: 1 },
      { id: 'f3', x: 9.6, y: 1.2, depth: 9, size: 3.6, shape: 'shard', rot: 1.2, lodge: 0 },
    ],
    tone: 0.62, seed: 911,
    film: null, items: { gauze: 6 },
    location: { kind: 'surgery', label: 'Operating table · Pillbox' }, bay: false, bloodWarn: false,
    vitals: { hr: 104, ecgRate: 104, rhythm: 'stach', spo2: 95, sys: 108, dia: 66, map: 80, rr: 20, bloodPct: 88, drip: 125, infusing: true },
  };

  /* ═════════════════════════════ 3D parts this app adds ═════════════════════════════ */
  const T3 = () => window.THREE;
  // elliptical section lofted along +Y: rows [{ y, w, t, x?, z? }]
  function loft(rows, seg = 12) {
    const THREE = T3(), g = new THREE.BufferGeometry(), pos = [], idx = [];
    rows.forEach(r => { for (let k = 0; k < seg; k++) { const a = (k / seg) * TAU; pos.push((r.x || 0) + Math.cos(a) * r.w / 2, r.y, (r.z || 0) + Math.sin(a) * r.t / 2); } });
    for (let i = 0; i < rows.length - 1; i++) for (let k = 0; k < seg; k++) { const a = i * seg + k, b = i * seg + ((k + 1) % seg), c = a + seg, d = b + seg; idx.push(a, d, b, a, c, d); }
    const n = pos.length / 3, r0 = rows[0], r1 = rows[rows.length - 1];
    pos.push(r0.x || 0, r0.y, r0.z || 0, r1.x || 0, r1.y, r1.z || 0);
    for (let k = 0; k < seg; k++) { idx.push(n, k, (k + 1) % seg); const o = (rows.length - 1) * seg; idx.push(n + 1, o + (k + 1) % seg, o + k); }
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
    return g;
  }
  function materials() {
    const THREE = T3();
    return {
      steel: new THREE.MeshStandardMaterial({ color: 0xdfe4e8, metalness: 1, roughness: 0.2 }),
      satin: new THREE.MeshStandardMaterial({ color: 0xc6cdd2, metalness: 1, roughness: 0.34 }),
      dark: new THREE.MeshStandardMaterial({ color: 0x6e767c, metalness: 1, roughness: 0.42 }),
      white: new THREE.MeshPhysicalMaterial({ color: 0xf1f4f4, roughness: 0.4, clearcoat: 0.35, clearcoatRoughness: 0.3 }),
      teal: new THREE.MeshPhysicalMaterial({ color: 0x0fb3a6, roughness: 0.35, clearcoat: 0.5 }),
      clear: new THREE.MeshPhysicalMaterial({ color: 0xeaf8ff, roughness: 0.08, transparent: true, opacity: 0.4, clearcoat: 1, clearcoatRoughness: 0.05, depthWrite: false }),
      tubing: new THREE.MeshPhysicalMaterial({ color: 0xe9eeef, roughness: 0.3, transparent: true, opacity: 0.85, clearcoat: 0.6 }),
    };
  }
  // engine-compatible tool object (NZA3D tools.use accepts it)
  function shell(name, built, pose) {
    const THREE = T3();
    const t = Object.assign(built, { name, pose: Object.assign({}, pose), base: Object.assign({}, pose), press: 0, _p: new THREE.Vector3(), _q: new THREE.Quaternion(), _init: false });
    t.group.visible = false;
    t.group.traverse(c => { if (c.isMesh) { c.castShadow = true; } });
    t.tipWorld = () => t.group.getWorldPosition(new THREE.Vector3());
    if (!t.set) t.set = () => {};
    return t;
  }
  // ring-handled bullet forceps: tip at the origin, handle along +Y; set({ open 0..1 })
  function buildRingForceps(M) {
    const THREE = T3(), g = new THREE.Group(), halves = [], PIV = 0.036;
    for (const sd of [-1, 1]) {
      const h = new THREE.Group(); h.position.set(0, PIV, 0); g.add(h); halves.push(h);
      h.add(new THREE.Mesh(loft([
        { y: -PIV, w: 0.0012, t: 0.0015, x: sd * 0.0005 }, { y: -PIV + 0.004, w: 0.0018, t: 0.002, x: sd * 0.0008 },
        { y: -PIV + 0.016, w: 0.0025, t: 0.0025, x: sd * 0.001 }, { y: -0.002, w: 0.0033, t: 0.003, x: sd * 0.0011 },
      ], 12), M.satin));
      for (let i = 0; i < 7; i++) { const r = new THREE.Mesh(new THREE.BoxGeometry(0.0009, 0.00042, 0.0022), M.dark); r.position.set(sd * 0.0002, -PIV + 0.0012 + i * 0.0016, 0); h.add(r); }
      h.add(new THREE.Mesh(loft([
        { y: 0.0, w: 0.0033, t: 0.003, x: sd * 0.0004 }, { y: 0.02, w: 0.003, t: 0.0028, x: -sd * 0.0022 },
        { y: 0.056, w: 0.003, t: 0.0027, x: -sd * 0.0054 }, { y: 0.09, w: 0.0032, t: 0.0028, x: -sd * 0.0088 },
      ], 12), M.satin));
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0084, 0.0016, 12, 36), M.steel);
      ring.position.set(-sd * 0.0138, 0.1, 0); ring.rotation.z = -sd * 0.25; h.add(ring);
      for (let i = 0; i < 4; i++) { const r = new THREE.Mesh(new THREE.BoxGeometry(0.0016, 0.0011, 0.0018), M.dark); r.position.set(-sd * 0.0064, 0.074 + i * 0.0016, sd * 0.0006); r.rotation.z = -sd * 0.6; h.add(r); }
    }
    const lock = new THREE.Mesh(new THREE.CylinderGeometry(0.0028, 0.0028, 0.0042, 24).rotateX(Math.PI / 2), M.satin);
    lock.scale.set(1, 1.35, 1); lock.position.set(0, PIV, 0); g.add(lock);
    const screw = new THREE.Mesh(new THREE.CylinderGeometry(0.0011, 0.0011, 0.0045, 16).rotateX(Math.PI / 2), M.steel);
    screw.position.set(0, PIV, 0); g.add(screw);
    const api = { group: g, open: 0, set(p) { if (p.open !== undefined) { api.open = clamp(p.open, 0, 1); halves[0].rotation.z = -api.open * 0.15; halves[1].rotation.z = api.open * 0.15; } } };
    api.set({ open: 0.3 });
    return api;
  }
  // Yankauer suction tip with tubing; set({ flow 0..1 }) shows blood running up the tube
  function buildSuction(M) {
    const THREE = T3(), g = new THREE.Group();
    const blood = new THREE.MeshBasicMaterial({ color: 0x6a0707, transparent: true, opacity: 0, depthWrite: false });
    const tip = new THREE.Mesh(new THREE.SphereGeometry(0.0033, 20, 14), M.clear); tip.scale.set(1, 1.3, 1); tip.position.y = 0.0036; g.add(tip);
    const c1 = new THREE.CatmullRomCurve3([new THREE.Vector3(0, 0.005, 0), new THREE.Vector3(0, 0.03, 0.002), new THREE.Vector3(0, 0.055, 0.009), new THREE.Vector3(0, 0.07, 0.016)]);
    const c2 = new THREE.CatmullRomCurve3([new THREE.Vector3(0, 0.07, 0.016), new THREE.Vector3(0, 0.12, 0.03), new THREE.Vector3(0, 0.2, 0.046)]);
    g.add(new THREE.Mesh(new THREE.TubeGeometry(c1, 40, 0.0027, 14, false), M.clear));
    g.add(new THREE.Mesh(new THREE.TubeGeometry(c1, 40, 0.0016, 10, false), blood));
    g.add(new THREE.Mesh(new THREE.TubeGeometry(c2, 40, 0.0058, 18, false), M.clear));
    g.add(new THREE.Mesh(new THREE.TubeGeometry(c2, 40, 0.0041, 12, false), blood));
    const up = new THREE.Vector3(0, 1, 0);
    for (let i = 0; i < 7; i++) {
      const u = 0.18 + i * 0.09, p = c2.getPoint(u);
      const r = new THREE.Mesh(new THREE.TorusGeometry(0.006, 0.0007, 8, 24).rotateX(Math.PI / 2), M.clear);
      r.position.copy(p); r.quaternion.setFromUnitVectors(up, c2.getTangent(u)); g.add(r);
    }
    const end = c2.getPoint(1), tan = c2.getTangent(1);
    const con = new THREE.Mesh(new THREE.CylinderGeometry(0.0064, 0.0054, 0.014, 20), M.teal);
    con.position.copy(end).addScaledVector(tan, 0.005); con.quaternion.setFromUnitVectors(up, tan); g.add(con);
    const c3 = new THREE.CatmullRomCurve3([end.clone().addScaledVector(tan, 0.01), end.clone().addScaledVector(tan, 0.045).add(new THREE.Vector3(0.006, 0, 0)), end.clone().add(new THREE.Vector3(0.05, 0.07, 0.02)), end.clone().add(new THREE.Vector3(0.12, 0.09, 0.0))]);
    g.add(new THREE.Mesh(new THREE.TubeGeometry(c3, 40, 0.0042, 14, false), M.tubing));
    return { group: g, set(p) { if (p.flow !== undefined) blood.opacity = clamp(p.flow, 0, 1) * 0.92; } };
  }
  // sponge stick soaked in povidone-iodine; set({ load 0..1 (dry → wet), squash 0..1 })
  function buildSwab(M) {
    const THREE = T3(), g = new THREE.Group();
    g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.0021, 0.0021, 0.15, 14).translate(0, 0.096, 0), M.white));
    g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.0034, 0.0034, 0.012, 16).translate(0, 0.024, 0), M.teal));
    const geo = new THREE.BoxGeometry(0.014, 0.02, 0.0095, 8, 10, 6);
    const p = geo.attributes.position, v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) {
      v.set(p.getX(i) / 0.007, p.getY(i) / 0.01, p.getZ(i) / 0.00475);
      const n = v.clone().normalize();
      v.lerp(n.multiplyScalar(Math.max(Math.abs(v.x), Math.abs(v.y), Math.abs(v.z))), 0.55);
      p.setXYZ(i, v.x * 0.007, v.y * 0.01 + 0.0098, v.z * 0.00475);
    }
    geo.computeVertexNormals();
    const mat = new THREE.MeshStandardMaterial({ color: 0x7a2a0a, roughness: 0.93 });
    const head = new THREE.Mesh(geo, mat); g.add(head);
    const dry = new THREE.Color(0xe2c9a6), wet = new THREE.Color(0x7a2a0a);
    return { group: g, set(q) { if (q.load !== undefined) mat.color.copy(dry).lerp(wet, clamp(q.load, 0, 1)); if (q.squash !== undefined) head.scale.y = 1 - clamp(q.squash, 0, 1) * 0.22; } };
  }
  // deformed bullet (mushroomed jacket, lead showing) or a jagged steel shard; size = length (mm)
  function buildFragment(f, seed) {
    const THREE = T3(), R = rng(seed), L = clamp(+f.size || 8, 2, 20) * MM;
    let geo;
    const cols = [];
    if (f.shape === 'bullet') {
      const r = L * 0.37;
      const prof = [[0, 0], [r * 0.9, 0], [r, L * 0.07], [r, L * 0.5], [r * 0.93, L * 0.7], [r * 0.72, L * 0.86], [r * 0.38, L * 0.97], [0, L]];
      geo = new THREE.LatheGeometry(prof.map(([x, y]) => new THREE.Vector2(x, y - L / 2)), 30, 0, TAU);
      const p = geo.attributes.position, ph = R() * 6;
      for (let i = 0; i < p.count; i++) {
        let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
        const a = Math.atan2(z, x), up = smooth(-0.05 * L, 0.35 * L, y);
        // mushroomed nose: flattened, flared, torn petals
        const petal = 1 + 0.18 * Math.sin(a * 5 + ph) * up + 0.08 * Math.sin(a * 11 + ph * 2) * up;
        const flare = 1 + 0.42 * up;
        x *= flare * petal; z *= flare * petal;
        if (y > 0.18 * L) y = 0.18 * L + (y - 0.18 * L) * 0.32 + Math.sin(a * 3 + ph) * 0.03 * L;
        // dents
        const dent = Math.max(0, Math.sin(a * 2 + ph * 3) * Math.sin(y / L * 9 + ph)) * 0.06;
        x *= 1 - dent; z *= 1 - dent;
        p.setXYZ(i, x, y, z);
        const lead = smooth(0.08 * L, 0.24 * L, y) * (0.6 + 0.4 * Math.abs(Math.sin(a * 5 + ph)));
        cols.push(lerp(0.76, 0.56, lead), lerp(0.45, 0.58, lead), lerp(0.27, 0.6, lead));
      }
    } else {
      geo = new THREE.IcosahedronGeometry(L / 2, 1);
      const p = geo.attributes.position, key = {};
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
        const k = `${Math.round(x * 1e5)},${Math.round(y * 1e5)},${Math.round(z * 1e5)}`;
        if (!key[k]) key[k] = 0.62 + R() * 0.55;
        const s = key[k];
        p.setXYZ(i, x * s * 1.35, y * s * 0.95, z * s * 0.45);
        const rust = Math.max(0, Math.sin(x * 900 + y * 700) * 0.5 + R() * 0.2);
        cols.push(lerp(0.42, 0.5, rust), lerp(0.44, 0.31, rust), lerp(0.46, 0.2, rust));
      }
    }
    geo.setAttribute('color', new THREE.Float32BufferAttribute(cols, 3));
    geo.computeVertexNormals();
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, metalness: f.shape === 'bullet' ? 0.92 : 0.8, roughness: f.shape === 'bullet' ? 0.36 : 0.55, color: 0xffffff });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.castShadow = true; mesh.receiveShadow = true; mesh.visible = false;
    mesh.userData.thick = f.shape === 'bullet' ? L * 0.74 : L * 0.42;
    return mesh;
  }

  NZA.app('bullet', {
    escClose: false, full: true, noscale: true, camInput: false,

    init(el) {
      this.el = el;
      el.innerHTML = `
        <div class="bx-stage"></div>
        <div class="bx-tags"></div>
        <div class="bx-ui">
          <header class="bx-strip nza-hud solid"></header>
          <div class="bx-notes"></div>
          <aside class="bx-plan nza-hud solid"></aside>
          <aside class="bx-dev nza-hud solid"></aside>
          <aside class="bx-film nza-hud solid"></aside>
          <div class="bx-result-wrap"></div>
        </div>
        <div class="bx-cur"><svg viewBox="0 0 46 46"><circle class="bg" cx="23" cy="23" r="19"/><circle class="fg" cx="23" cy="23" r="19" stroke-dasharray="0 120"/></svg><span class="tx"></span></div>
        <div class="bx-load"><div class="in"><span class="ring"></span><span class="lt"></span></div></div>`;
      const q = s => el.querySelector(s);
      this.stage = q('.bx-stage'); this.tags = q('.bx-tags'); this.ui = q('.bx-ui');
      this.stripEl = q('.bx-strip'); this.notesEl = q('.bx-notes'); this.planEl = q('.bx-plan');
      this.devEl = q('.bx-dev'); this.filmEl = q('.bx-film'); this.resWrap = q('.bx-result-wrap');
      this.cur = q('.bx-cur'); this.curFg = q('.bx-cur .fg'); this.curTx = q('.bx-cur .tx'); this.loadEl = q('.bx-load');
      this.mx = window.innerWidth / 2; this.my = window.innerHeight / 2;
      window.addEventListener('mousemove', e => { this.mx = e.clientX; this.my = e.clientY; });
      const heard = e => { if (e.isTrusted) this.heard = true; };
      window.addEventListener('pointerdown', heard, true);
      window.addEventListener('keydown', heard, true);
      this.keys = {};
      ['1', '2', '3', '4', '5', '6', '7', '8'].forEach(k => { this.keys[k] = () => this.pickTool(k); });
      this.keys.x = this.keys.X = () => this.pickTool('X');
      this.keys[' '] = e => { if (!e.repeat) this.spreadKey(true); };
      this.keys.q = this.keys.Q = () => this.blade(-1);
      this.keys.e = this.keys.E = () => this.blade(1);
      this.keys.a = this.keys.A = () => this.rock(-1);
      this.keys.d = this.keys.D = () => this.rock(1);
      this.keys.l = this.keys.L = () => this.leaveRest();
      this.keys.Enter = () => { if (this.resultShown && this.canClose) { this.closeNow(); return true; } return false; };
      this.keysUp = { ' ': () => this.spreadKey(false) };
    },

    /* ═════════════ lifecycle ═════════════ */
    open(d) {
      this.teardown();
      LOC = d.locale || {};
      this.d = d;
      this.cfg = Object.assign({}, DEFAULTS, d.cfg || {});
      this.cfg.weights = Object.assign({}, DEFAULTS.weights, (d.cfg && d.cfg.weights) || {});
      this.alive = true; this.resultShown = false; this.canClose = false; this.finished = false; this.result = null;
      this.vit = Object.assign({}, d.vitals || {});
      this.loadEl.classList.remove('out');
      this.loadEl.querySelector('.lt').textContent = T('loading', 'Preparing the surgical field…');
      this.resWrap.innerHTML = '';
      [this.stripEl, this.planEl, this.devEl, this.notesEl].forEach(x => { x.style.display = ''; });
      this.filmEl.classList.remove('on');
      const token = this.openToken = (this.openToken || 0) + 1;
      requestAnimationFrame(() => requestAnimationFrame(() => { if (this.alive && token === this.openToken) this.boot(); }));
    },
    close() { this.teardown(); },

    teardown() {
      this.alive = false;
      if (this.S) { try { this.S.dispose(); } catch (e) { console.error('[bullet] dispose', e); } this.S = null; }
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      if (this.ecg) { this.ecg.stop(); this.ecg = null; }
      if (this.pleth) { this.pleth.stop(); this.pleth = null; }
      if (this.bayHold) { this.bayHold.destroy(); this.bayHold = null; }
      if (this.fallbackTimer) { clearInterval(this.fallbackTimer); this.fallbackTimer = null; }
      if (this.demoVitals) { clearInterval(this.demoVitals); this.demoVitals = null; }
      clearTimeout(this.stepTimer);
      if (this.cur) this.cur.classList.remove('on');
      if (this.stage) { this.stage.innerHTML = ''; this.stage.className = 'bx-stage'; }
      if (this.tags) this.tags.innerHTML = '';
      this.g = null; this.frags = null; this.tl = null;
    },

    msg: {
      vitals(v) { NZA.apps.bullet.onVitals(v || {}); },
      result(o) { NZA.apps.bullet.showOutcome(o || {}); },
      abort() { NZA.apps.bullet.teardown(); NZA.closeLocal('bullet'); },
    },

    preview() {
      NZA.mock('bullet:finish', r => new Promise(res => setTimeout(() => {
        const s = (r && r.score) || 0;
        res({ ok: true, outcome: { score: s, grade: s >= 95 ? 'S' : s >= 85 ? 'A' : s >= 72 ? 'B' : s >= 58 ? 'C' : s >= 40 ? 'D' : 'F', msg: T('demo_msg', 'Projectile removed, wound closed and dressed.') } });
      }, 700)));
      NZA.mock('bullet:abort', { ok: true });
      NZA.mock('bullet:flinch', { ok: true });
      NZA.mock('bullet:exitBay', { ok: true });
      const shrap = /shrapnel/.test(location.search);
      const data = JSON.parse(JSON.stringify(shrap ? DEMO_SHRAPNEL : DEMO));
      NZA.demo('bullet', Object.assign(data, { locale: {} }));
      // the monitor drifts a little in the preview (in game the Lua watch pushes 'vitals')
      clearInterval(this.demoVitals);
      const base = data.vitals;
      this.demoVitals = setInterval(() => {
        if (!this.alive) return;
        const loss = this.g ? this.g.loss : 0;
        const j = () => (Math.random() - 0.5) * 2;
        this.onVitals(Object.assign({}, base, { hr: Math.round(base.hr + loss * 0.05 + j()), ecgRate: Math.round(base.hr + loss * 0.05), spo2: Math.round(base.spo2 + (Math.random() < 0.2 ? -1 : 0)), sys: Math.round(base.sys - loss * 0.04 + j()), dia: Math.round(base.dia - loss * 0.02), bloodPct: Math.max(40, base.bloodPct - loss / 50) }));
      }, 1000);
    },

    /* ═════════════ boot ═════════════ */
    boot() {
      const d = this.d, cfg = this.cfg;
      const inj = Object.assign({}, DEMO.injury, d.injury || {});
      this.inj = inj;
      this.buildHud();
      if (!window.NZA3D || !NZA3D.supported()) return this.fallback();
      const seed = (+d.seed || hash(`${inj.id}:${(d.patient && d.patient.name) || ''}`)) >>> 0;
      const R = rng(seed);
      this.R = R;
      const region = inj.region || 'chest';
      const kind = String(region).replace(/^[lr]_/, '');
      const limb = /arm|leg/.test(region);
      this.R0 = limb ? (/lower/.test(region) ? 0.034 : 0.04) : 0.05;
      this.fat = FAT[kind] || 10;
      this.boneDepth = BONE[kind] || 40;
      let S;
      try {
        S = NZA3D.createScene(this.stage, {
          tone: d.tone !== undefined ? +d.tone : 0.3, region, sex: (d.patient && d.patient.sex) || 'm', seed,
          hair: d.hair !== undefined && d.hair !== null ? +d.hair : null, quality: cfg.quality,
          drape: { radius: this.R0, uv: [0.5, 0.5] },
          focus: { uv: [0.5, 0.5], size: [this.R0 * 1.5, this.R0 * 1.5], view: this.R0 * 2.7 },
        });
      } catch (e) {
        console.error('[bullet] 3D scene', e);
        return this.fallback();
      }
      this.S = S;
      this.entryUv = [0.5, 0.5];
      // fragments (mm offsets from the entry wound, +y toward the medic)
      const list = Array.isArray(d.fragments) && d.fragments.length ? d.fragments : [{ id: 'f1', x: 5, y: -2, depth: +inj.depth || 20, size: inj.type === 'gunshot' ? 10 : 5, shape: inj.type === 'gunshot' ? 'bullet' : 'shard', rot: 0.6 }];
      this.frags = list.map((f, i) => {
        const x = clamp(+f.x || 0, -this.R0 / MM * 0.55, this.R0 / MM * 0.55), y = clamp(+f.y || 0, -this.R0 / MM * 0.55, this.R0 / MM * 0.55);
        const depth = clamp(+f.depth || 18, 4, Math.max(8, this.boneDepth - 3));
        return {
          id: String(f.id || `f${i + 1}`), n: i + 1, x, y, depth, size: clamp(+f.size || 6, 2, 18), shape: f.shape === 'bullet' ? 'bullet' : 'shard',
          rot: +f.rot || 0, lodge: clamp(+f.lodge || 0, 0, 1), uv: S.stToUv(x * MM, y * MM),
          found: false, how: '', exposed: false, out: false, prog: 0, tint: 0, mesh: null,
        };
      });
      this.paintInitial(R);
      this.buildParts(seed);

      const ideal = this.idealCut();
      const g = this.g = {
        t: 0, step: 1, tool: null, lmb: false, done: {}, skipped: {}, uiT: 0, poolT: 0, loss: 0, lossEv: [],
        pain0: d.patient && d.patient.conscious === false ? 0 : clamp(+inj.pain || 50, 15, 100) * (d.patient && d.patient.numb ? 0.25 : 1),
        painSpike: 0, pain: 0, flinches: 0, lastSay: -9,
        pr: { on: false, depth: 0, start: null, track: false, target: null, blocked: false, err: 0, contact: null, falses: 0, palped: false, steer: null, bone: false },
        film: { open: false, used: false },
        io: { load: 1, redip: 0, last: null, dist: 0, rMax: 0, back: 0, backT: -9, dips: 0, cov: 0, center: null, mask: null },
        cut: { blade: cfg.bladeStart, path: [], drawing: false, w: null, L: 0, strokes: 0, ext: 0, muscle: false, deepMax: 0, shallow: 0, fast: 0, jag: 0, covered: false, ideal, lastBuild: 0, dirty: false, speed: 0, refused: 0 },
        ex: { spread: 0, space: false, overT: 0, tears: 0, applied: -1 },
        xt: { grip: null, strength: 0, speed: 0, lastY: 0, slips: 0, misses: 0, pushes: 0, rockSide: 0, out: [], left: false, fly: [] },
        bl: { rate: 0, boost: 0 },
        hm: { start: 0, press: 0 },
        su: { ml: 0, flowT: 0 },
        gz: { have: Math.min((d.items && +d.items.gauze) || 0, cfg.gauzeMax), used: 0, swab: null, stainT: 0, absorbed: 0 },
        sut: { N: 0, list: [], misses: 0, drag: null, last: null },
        dr: { D: null, rub: false, cover: 0, settledT: 0, warnT: 0 },
      };
      g.pain = g.pain0;
      S.layers.decay('wet', 0.05);
      this.setBleed();

      // compile shaders behind the loading veil
      const mine = [this.tl.swab, this.tl.suction, this.tl.forceps];
      mine.forEach(t => { t.group.visible = true; t.group.position.set(0, 0.02, 0); });
      this.frags.forEach(f => { f.mesh.visible = true; });
      try { S.prewarm(['probe', 'scalpel', 'gauze', 'needleDriver'], true); } catch (e) { console.error('[bullet] prewarm', e); }
      mine.forEach(t => { t.group.visible = false; });
      this.frags.forEach(f => { f.mesh.visible = false; });

      S.on('frame', dt => this.frame(dt));
      S.on('down', e => this.down(e));
      S.on('up', e => this.up(e));
      S.start();
      this.buildPanel();
      this.enterStep(1, true);
      if (d.bloodWarn) setTimeout(() => { if (this.alive && this.g === g) this.flash('bad', T('warn_blood_flash', 'Low blood volume and nothing running — hang a unit before you cut.'), 4200); }, 900);
      setTimeout(() => this.loadEl.classList.add('out'), 140);
    },

    // entry wound, bruising, dried blood, powder stippling, shrapnel peppering
    paintInitial(R) {
      const S = this.S, inj = this.inj, gun = inj.type === 'gunshot', sev = clamp(+inj.severity || 2, 1, 4);
      const jit = (uv, mm) => [uv[0] + (R() - 0.5) * mm * MM / S.patch.W, uv[1] + (R() - 0.5) * mm * MM / S.patch.H];
      this.entry = S.wounds.add({ type: 'gunshot', uv: this.entryUv, radius: (gun ? 3.3 : 2.4) * MM, ring: (gun ? 1.7 : 0.9) * MM, depth: 9 * MM, jagged: gun ? 0.35 : 0.85, seed: 17 });
      this.sats = [];
      if (!gun) {
        const n = Math.min(3, this.frags.length + 1);
        for (let k = 0; k < n; k++) {
          const a = R() * TAU, r = (6 + R() * 10) * MM;
          this.sats.push(S.wounds.add({ type: 'gunshot', uv: S.stToUv(Math.cos(a) * r, Math.sin(a) * r), radius: (0.8 + R() * 0.6) * MM, ring: 0.5 * MM, depth: 2.5 * MM, jagged: 0.9, seed: 40 + k }));
        }
        for (let k = 0; k < 40; k++) { const a = R() * TAU, r = (3 + R() * 22) * MM; S.layers.paint('clot', S.stToUv(Math.cos(a) * r, Math.sin(a) * r), (0.2 + R() * 0.4) * MM, 0.5 + R() * 0.4, { hardness: 0.5 }); }
      }
      // dried blood ring + a trickle toward the medic, a bruise
      S.layers.splat('clot', this.entryUv, (gun ? 4.5 : 3.5) * MM, 0.5, { seed: 3, count: 8 });
      S.layers.paint('blood', this.entryUv, (gun ? 3 : 2.2) * MM, 0.55, { hardness: 0.3 });
      const t0 = S.uvToST(this.entryUv);
      S.layers.stroke('clot', this.entryUv, S.stToUv(t0[0] + (R() - 0.5) * 0.004, t0[1] + 0.012 + R() * 0.008), 0.0008, 0.32, { hardness: 0.4, grain: 0.4, grainScale: 120 });
      S.layers.splat('bruise', this.entryUv, (9 + sev * 2.5) * MM, 0.16 + sev * 0.03, { seed: 5, count: 7 });
      if (gun && R() < 0.65) {
        // powder stippling: a close shot leaves burnt grains around the hole
        for (let k = 0; k < 70; k++) S.layers.paint('soot', jit(this.entryUv, 16), (0.12 + R() * 0.22) * MM, 0.45 + R() * 0.45, { hardness: 0.6 });
      }
      for (let k = 0; k < 18; k++) S.layers.paint('clot', jit(this.entryUv, 14), (0.1 + R() * 0.3) * MM, 0.2 + R() * 0.3, { hardness: 0.45 });
      const cont = clamp((+inj.contamination || 0) / 100, 0, 1);
      for (let k = 0; k < Math.round(cont * 30); k++) S.layers.paint('grime', jit(this.entryUv, 26), (0.3 + R() * 0.9) * MM, 0.12 + R() * 0.2, { hardness: 0.3, grain: 0.7, grainScale: 140 });
    },

    buildParts(seed) {
      const S = this.S, M = materials();
      this.M = M;
      this.tl = {
        swab: shell('swab', buildSwab(M), { lift: 0.002, pressLift: 0.0004, tilt: 0.95, yaw: 1.05, roll: 0, shadow: 0.022 }),
        suction: shell('suction', buildSuction(M), { lift: 0.004, pressLift: -0.0015, tilt: 0.7, yaw: 1.0, roll: 0, shadow: 0.014 }),
        forceps: shell('forceps', buildRingForceps(M), { lift: 0.005, pressLift: -0.0025, tilt: 0.62, yaw: 1.3, roll: 0, shadow: 0.016 }),
      };
      Object.values(this.tl).forEach(t => S.scene.add(t.group));
      this.frags.forEach((f, i) => { f.mesh = buildFragment(f, seed + i * 77); S.scene.add(f.mesh); });
      this.fragBlood = new (T3().Color)(0.5, 0.06, 0.05);
      this._v = new (T3().Vector3)(); this._w = new (T3().Vector3)();
    },

    /* ═════════════ HUD ═════════════ */
    buildHud() {
      const d = this.d;
      const inj = this.inj;
      const name = (d.patient && d.patient.name) || T('patient', 'Patient');
      const loc = d.location || {};
      const mid = d.bay
        ? `<div class="bx-exit"><span class="bx-hk"><kbd>${esc(T('key_backspace', 'BACKSPACE'))}</kbd><i></i></span><b>${esc(T('exit_bay', 'Exit treatment bay'))}</b></div>`
        : `<div class="bx-loc">${icon(loc.kind === 'surgery' ? 'hospital' : loc.kind === 'bed' ? 'bed' : 'medkit')}<b>${esc(loc.label || T('loc_field', 'Field surgery'))}</b></div>`;
      this.stripEl.innerHTML = `
        <div class="bx-tr">
          <canvas class="cv-ecg"></canvas><canvas class="cv-pleth"></canvas>
          <span class="l1">II</span><span class="l2">PLETH</span>
          <div class="ft"><span class="rh"></span><span class="dr"></span></div>
        </div>
        <div class="bx-mid">${mid}<div class="pt"><span class="dot"></span>${esc(name)}${d.patient && d.patient.bloodType ? ` · <b>${esc(d.patient.bloodType)}</b>` : ''} · ${esc(inj.label || '')} · ${esc(inj.regionLabel || '')}</div></div>
        <div class="bx-tiles">
          <div class="tile hr"><span class="l">${esc(T('v_hr', 'HR'))}</span><b>--</b><small>${esc(T('u_bpm', 'bpm'))}</small></div>
          <div class="tile sp"><span class="l">${esc(T('v_spo2', 'SpO₂'))}</span><b>--</b><small>%</small></div>
          <div class="tile bp"><span class="l">${esc(T('v_nibp', 'NIBP'))}</span><b>--</b><small></small></div>
          <div class="tile bl"><span class="l">${esc(T('v_loss', 'Blood loss'))}</span><b>0</b><small>${esc(T('u_ml', 'mL'))}</small></div>
        </div>`;
      const q = s => this.stripEl.querySelector(s);
      this.ecg = NZA.vitals.Trace(q('.cv-ecg'), { type: 'ecg', rhythm: this.vit.rhythm || 'sinus', rate: this.vit.ecgRate || this.vit.hr || 80, color: '#3ddc84', speed: 0.2, gain: 0.34 });
      this.pleth = NZA.vitals.Trace(q('.cv-pleth'), { type: 'pleth', rhythm: this.vit.rhythm || 'sinus', rate: this.vit.ecgRate || this.vit.hr || 80, color: '#3fd0ff', speed: 0.2, gain: 0.3, line: 1.5 });
      if (d.bay) {
        const hk = this.stripEl.querySelector('.bx-exit');
        this.bayHold = NZA.ui.Hold({ key: 'Backspace', seconds: 1.0, el: hk, onProgress: p => { hk.style.setProperty('--p', p); hk.classList.toggle('on', p > 0); }, onDone: () => this.exitBay() });
      }
      this.planEl.innerHTML = `
        <div class="hd"><span class="nza-label">${esc(T('plan', 'Procedure'))}</span><span class="tm">00:00</span></div>
        <ol></ol>
        <div class="ft"></div>`;
      this.devEl.innerHTML = '';
      this.renderStrip();
      this.renderNotes();
    },
    onVitals(v) {
      this.vit = Object.assign(this.vit || {}, v);
      if (this.ecg) this.ecg.set({ rhythm: this.vit.rhythm || 'sinus', rate: this.vit.ecgRate || this.vit.hr || 0 });
      if (this.pleth) this.pleth.set({ rhythm: this.vit.rhythm || 'sinus', rate: this.vit.ecgRate || this.vit.hr || 0, amp: clamp((this.vit.map || 80) / 85, 0.25, 1) });
      this.renderStrip();
      this.renderNotes();
    },
    renderStrip() {
      const v = this.vit || {}, el = this.stripEl;
      if (!el || !el.querySelector('.bx-tiles')) return;
      const set = (cls, val, tone, sub) => {
        const t = el.querySelector(`.tile.${cls}`); if (!t) return;
        const b = t.querySelector('b'); const s = String(val);
        if (b.textContent !== s) b.textContent = s;
        t.classList.toggle('alarm', tone === 'red'); t.classList.toggle('warn', tone === 'amber');
        if (sub !== undefined) { const sm = t.querySelector('small'); if (sm.textContent !== sub) sm.textContent = sub; }
      };
      const hr = v.hr !== undefined ? Math.round(v.hr) : '--';
      set('hr', hr, (v.hr > 130 || v.hr < 45) ? 'red' : v.hr > 110 ? 'amber' : '');
      set('sp', v.spo2 !== undefined ? Math.round(v.spo2) : '--', v.spo2 < 90 ? 'red' : v.spo2 < 94 ? 'amber' : '');
      set('bp', v.sys !== undefined ? `${Math.round(v.sys)}/${Math.round(v.dia || 0)}` : '--', v.sys < 85 ? 'red' : v.sys < 100 ? 'amber' : '', v.map !== undefined ? T('v_map', 'MAP %s mmHg', Math.round(v.map)) : T('u_mmhg', 'mmHg'));
      const loss = this.g ? Math.round(this.g.loss) : 0;
      set('bl', loss, loss >= 250 ? 'red' : loss >= 120 ? 'amber' : '', v.bloodPct !== undefined ? T('v_blood', 'mL · blood %s%', Math.round(v.bloodPct)) : T('u_ml', 'mL'));
      const rh = el.querySelector('.ft .rh'), dr = el.querySelector('.ft .dr');
      const rt = `${String(v.rhythm || 'sinus').toUpperCase()} · ${hr} ${T('u_bpm_up', 'BPM')}`;
      if (rh.textContent !== rt) rh.textContent = rt;
      const drip = Math.round(+v.drip || 0);
      const dh = drip > 0 ? `${T('drip', 'DRIP')} <b>${drip}</b> ${esc(T('u_mlmin', 'mL/min'))}` : `${T('drip', 'DRIP')} <b class="off">${esc(T('drip_off', 'NONE'))}</b>`;
      if (dr.innerHTML !== dh) dr.innerHTML = dh;
    },
    renderNotes() {
      const d = this.d || {}, v = this.vit || {};
      const notes = [];
      const lowBlood = v.bloodPct !== undefined ? v.bloodPct < 85 : true;
      if (d.bloodWarn && !v.infusing && lowBlood) notes.push(['red', 'bloodbag', T('n_blood', 'Blood first'), T('n_blood_t', 'Surgery costs the patient blood — hang a unit on the IV stand before you open the wound.')]);
      if (this.g && this.g.pain0 >= 35 && !(d.patient && d.patient.numb) && this.g.step <= 5) notes.push(['amber', 'syringe', T('n_pain', 'Not numbed'), T('n_pain_t', 'The patient is awake and feels everything. Expect flinches.')]);
      const html = notes.map(n => `<div class="note-x ${n[0]}"><span class="ni">${icon(n[1])}</span><div><b>${esc(n[2])}</b><p>${esc(n[3])}</p></div></div>`).join('');
      if (this.notesEl.innerHTML !== html) this.notesEl.innerHTML = html;
    },

    renderPlan(full) {
      const g = this.g;
      if (!g) return;
      const N = this.frags.length, found = this.frags.filter(f => f.found).length, out = g.xt.out.length;
      const vals = {
        1: g.done[1] ? (g.film.used ? T('plan_xray', 'X-ray') : `${found}/${N}`) : g.skipped[1] ? T('skipped', 'Skipped') : `${found}/${N}`,
        2: g.skipped[2] ? T('skipped', 'Skipped') : `${pct(g.io.cov)}%`,
        3: g.cut.w ? `${Math.round(g.cut.L || g.cut.w.length / MM)} mm` : '',
        4: g.step >= 4 ? `${pct(Math.min(1, g.ex.spread))}%` : '',
        5: `${out}/${N}`,
        6: g.cut.w && g.step >= 5 ? `${f1(this.bleedNow())}` : '',
        7: g.skipped[7] ? T('skipped', 'Skipped') : g.sut.N ? `${g.sut.list.length}/${g.sut.N}` : '',
        8: g.dr.D ? `${pct(g.dr.D.stuck)}%` : g.skipped[8] ? T('skipped', 'Skipped') : '',
      };
      const ol = STEPS.map(s => {
        const n = s.n;
        const cls = g.done[n] ? 'done' : g.skipped[n] ? 'skip' : g.step === n ? 'cur' : '';
        const b = g.done[n] ? icon('check') : g.skipped[n] ? icon('minus') : '';
        return `<li class="${cls}"><span class="b">${b}</span><span class="t">${esc(T(s.label[0], s.label[1]))}</span><span class="x">${esc(vals[n])}</span></li>`;
      }).join('');
      const olEl = this.planEl.querySelector('ol');
      if (full || olEl.innerHTML !== ol) olEl.innerHTML = ol;
      this.planEl.querySelector('.tm').textContent = NZA.fmt.time(g.t);
      const ft = [];
      ft.push(`<span class="bx-chip ${out === N ? 'teal' : ''}">${icon('crosshair')}${esc(T('chip_frags', 'Fragments %s/%s', out, N))}</span>`);
      if (g.gz.have) ft.push(`<span class="bx-chip">${icon('gauze')}${esc(T('chip_swabs', 'Gauze %s/%s', g.gz.used, g.gz.have))}</span>`);
      if (g.su.ml > 0.5) ft.push(`<span class="bx-chip">${icon('wind')}${esc(T('chip_suction', '%s mL', Math.round(g.su.ml)))}</span>`);
      if (g.flinches) ft.push(`<span class="bx-chip red">${esc(T('chip_flinch', 'Flinched ×%s', g.flinches))}</span>`);
      const fh = ft.join('');
      const ftEl = this.planEl.querySelector('.ft');
      if (ftEl.innerHTML !== fh) ftEl.innerHTML = fh;
    },

    /* the instrument card (left): probe depth, blade depth, retractor, grip/traction, bleeding */
    devMode() {
      const g = this.g;
      if (!g || this.finished) return '';
      if (g.tool === 'probe') return 'probe';
      if (g.tool === 'iodine') return 'swab';
      if (g.tool === 'scalpel') return 'blade';
      if (g.tool === 'forceps' && g.step === 5) return 'grip';
      if (g.step === 6) return 'bleed';
      if (g.step === 4 || (g.step === 5 && g.tool !== 'forceps')) return 'spread';
      return '';
    },
    layersHTML(maxD, opts = {}) {
      const fat = this.fat, bone = this.boneDepth;
      const y = mm => clamp(mm / maxD, 0, 1) * 100;
      const band = opts.band ? `<i class="band" style="top:${y(opts.band[0])}%;height:${y(opts.band[1]) - y(opts.band[0])}%"></i>` : '';
      const tip = opts.tip !== undefined ? `<i class="tip ${opts.tipTone || ''}" style="top:${y(opts.tip)}%"></i>` : '';
      const frs = (opts.frags || []).map(f => `<i class="fr" style="top:${y(f.depth)}%"></i>`).join('');
      return `<div class="dv-lay">
        <i class="ly skin" style="top:0;height:${y(2)}%"></i><i class="ly fat" style="top:${y(2)}%;height:${y(fat) - y(2)}%"></i>
        <i class="ly mus" style="top:${y(fat)}%;height:${y(bone) - y(fat)}%"></i><i class="ly bone" style="top:${y(bone)}%;height:${100 - y(bone)}%"></i>
        ${band}${frs}${tip}
        <span class="lt" style="top:${y(1)}%">${esc(T('ly_skin', 'Skin'))}</span><span class="lt" style="top:${y((2 + fat) / 2)}%">${esc(T('ly_fat', 'Fat'))}</span>
        <span class="lt" style="top:${y((fat + bone) / 2)}%">${esc(T('ly_muscle', 'Muscle'))}</span><span class="lt" style="top:${y(Math.min(maxD - 2, bone + 3))}%">${esc(T('ly_bone', 'Bone'))}</span>
      </div>`;
    },
    renderDev() {
      const g = this.g, cfg = this.cfg;
      const mode = this.devMode();
      const el = this.devEl;
      if (!mode || g.film.open) { el.classList.remove('on'); return; }
      el.classList.add('on');
      let html = '';
      if (mode === 'probe') {
        const pr = g.pr, maxD = this.boneDepth + 10;
        const tissue = pr.contact ? ['teal', T('ts_metal', 'Metal')] : pr.bone ? ['amber', T('ts_bone', 'Bone')] : !pr.on ? ['', T('ts_idle', 'Ready')]
          : pr.depth < 2 ? ['', T('ts_skin', 'Skin')] : pr.depth < this.fat ? ['', T('ts_fat', 'Fat')] : ['', T('ts_muscle', 'Soft tissue')];
        let feel;
        if (!pr.on) feel = T('feel_idle', 'Hold {LMB} in the wound to probe the track');
        else if (pr.contact) feel = T('feel_metal', 'Hard, gritty click — that is metal');
        else if (pr.blocked) feel = T('feel_blocked', 'False passage — release and start again');
        else if (!pr.track) feel = pr.palped ? T('feel_soft', 'Only soft tissue under the skin') : T('feel_press', 'Pressing on intact skin…');
        else if (pr.err > cfg.steerTol) feel = T('feel_resist', 'Resistance — steer along the arrow');
        else feel = T('feel_track', 'Sliding down the track');
        const steer = pr.on && pr.track && pr.steer && !pr.contact && pr.err > cfg.steerTol * 0.7
          ? `<div class="dv-steer ${pr.err > cfg.steerTol ? 'warn' : ''}"><span class="ar" style="transform:rotate(${(pr.steer * 180 / Math.PI).toFixed(0)}deg)">${icon('arrow-r')}</span>${esc(T('steer', 'Steer'))}</div>` : '';
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_probe', 'Probe depth'))}</span><span class="dv-tag ${tissue[0]}">${esc(tissue[1])}</span></div>
          <div class="dv-row"><div class="dv-l"><div class="dv-big ${pr.contact ? 'teal' : ''}"><b>${f1(pr.depth)}</b><span>mm</span></div>
          <div class="dv-sub">${NZA.rich(feel)}</div>${steer}</div>
          ${this.layersHTML(maxD, { tip: pr.depth, tipTone: pr.contact ? 'teal' : pr.blocked ? 'red' : '', frags: this.frags.filter(f => f.found && !f.out) })}</div>`;
      } else if (mode === 'swab') {
        const io = g.io, tech = clamp(1 - io.back * 0.15, 0, 1);
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_swab', 'Iodine swab'))}</span><span class="dv-tag ${io.redip > 0 ? 'amber' : ''}">${esc(io.redip > 0 ? T('swab_fresh', 'Fresh swab') : T('swab_n', 'Swab %s', io.dips + 1))}</span></div>
          <div class="dv-meters"><div class="dv-v"><span class="nza-label">${esc(T('dv_soak', 'Soaked'))}</span>${NZA.ui.meterHTML({ value: io.load, tone: io.load < 0.25 ? 'amber' : '' })}</div>
          <div class="dv-v"><span class="nza-label">${esc(T('dv_tech', 'Technique'))}</span>${NZA.ui.meterHTML({ value: tech, tone: tech < 0.6 ? 'red' : tech < 0.85 ? 'amber' : '' })}</div></div>
          <div class="dv-sub">${NZA.rich(io.back ? T('swab_back', 'Went back over the centre ×%s — work outward only.', io.back) : T('swab_tip', 'Small circles, from the incision site **outward**. Never come back to the centre.'))}</div>`;
      } else if (mode === 'blade') {
        const c = g.cut, band = this.band(), maxD = Math.max(this.fat + 14, 24);
        const tone = c.blade > band[1] + 3 ? 'red' : c.blade > band[1] ? 'amber' : c.blade < band[0] ? 'amber' : 'teal';
        const L = c.drawing && c.w ? c.w.length / MM : c.L;
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_blade', 'Blade depth'))}</span><span class="dv-tag ${tone === 'teal' ? 'teal' : tone}">${esc(c.blade > band[1] + 3 ? T('bd_muscle', 'Into muscle') : c.blade > band[1] ? T('bd_deep', 'Deep') : c.blade < band[0] ? T('bd_shallow', 'Shallow') : T('bd_ok', 'Skin + fat'))}</span></div>
          <div class="dv-row"><div class="dv-l"><div class="dv-big ${tone}"><b>${c.blade}</b><span>mm</span></div>
          <div class="dv-sub">${NZA.rich(T('bd_keys', '{Q} shallower · {E} deeper'))}</div>
          <div class="dv-kv"><span>${esc(T('cut_len', 'Length'))}</span><b>${Math.round(L || 0)} mm</b></div>
          <div class="dv-kv"><span>${esc(T('cut_aim', 'Aim'))}</span><b>~${Math.round(c.ideal)} mm</b></div></div>
          ${this.layersHTML(maxD, { band, tip: c.blade, tipTone: tone })}</div>`;
      } else if (mode === 'grip') {
        const x = g.xt, f = x.grip;
        const sp = clamp(x.speed / (cfg.pullSlip * 1.15), 0, 1), safe = cfg.pullSafe / (cfg.pullSlip * 1.15);
        const prog = f ? f.prog : 0;
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_extract', 'Extraction'))}</span><span class="dv-tag ${f ? 'teal' : ''}">${esc(f ? T('gr_held', 'Gripped') : T('gr_free', 'Open'))}</span></div>
          <div class="dv-row"><div class="dv-bars">
            <div class="vb"><span class="vl">${esc(T('dv_grip', 'Grip'))}</span><div class="vt"><i class="vf ${x.strength < 0.35 ? 'red' : x.strength < 0.6 ? 'amber' : ''}" style="height:${pct(f ? x.strength : 0)}%"></i></div></div>
            <div class="vb"><span class="vl">${esc(T('dv_traction', 'Traction'))}</span><div class="vt tr"><i class="zn" style="height:${(safe * 100).toFixed(1)}%"></i><i class="vf ${sp > 0.85 ? 'red' : sp > safe ? 'amber' : 'teal'}" style="height:${(sp * 100).toFixed(1)}%"></i></div></div>
            <div class="vb"><span class="vl">${esc(T('dv_out', 'Out'))}</span><div class="vt"><i class="vf white" style="height:${pct(prog)}%"></i></div></div>
          </div><div class="dv-l"><div class="dv-big"><b>${pct(prog)}</b><span>%</span></div>
          <div class="dv-sub">${NZA.rich(f && f.lodge > 0 ? T('gr_lodged', 'Lodged — rock it free: {A} {D}') : f ? T('gr_pull', 'Draw the mouse back **slowly**') : T('gr_aim', 'Aim at the fragment and press {LMB}'))}</div></div></div>`;
      } else if (mode === 'spread') {
        const s = g.ex.spread, clear = this.fieldClear();
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_retractor', 'Retractor'))}</span><span class="dv-tag ${s > cfg.tearAt ? 'red' : s >= cfg.exposeSpread ? 'teal' : ''}">${esc(s > cfg.tearAt ? T('rt_tear', 'Tearing') : s >= cfg.exposeSpread ? T('rt_open', 'Open') : T('rt_closed', 'Spread {Space}').replace(/[{}]/g, ''))}</span></div>
          <div class="dv-meters"><div class="dv-v"><span class="nza-label">${esc(T('dv_spread', 'Spread'))}</span>${NZA.ui.meterHTML({ value: clamp(s / 1.3, 0, 1), zone: [cfg.exposeSpread / 1.3, cfg.tearAt / 1.3], tone: s > cfg.tearAt ? 'red' : '' })}</div>
          <div class="dv-v"><span class="nza-label">${esc(T('dv_field', 'Field clear'))}</span>${NZA.ui.meterHTML({ value: clear, tone: clear < 1 - cfg.exposeBlood ? 'amber' : '' })}</div></div>
          <div class="dv-sub">${NZA.rich(T('rt_tip', 'Hold {Space} to spread the edges · suction {4} the blood away'))}</div>`;
      } else if (mode === 'bleed') {
        const b = this.bleedNow(), top = Math.max(g.hm.start, cfg.bleedDone * 3, b);
        html = `<div class="dv-hd"><span class="nza-label">${esc(T('dv_bleed', 'Bleeding'))}</span><span class="dv-tag ${b <= cfg.bleedDone ? 'teal' : 'red'}">${esc(b <= cfg.bleedDone ? T('bl_ok', 'Controlled') : T('bl_active', 'Active'))}</span></div>
          <div class="dv-row"><div class="dv-l"><div class="dv-big ${b <= cfg.bleedDone ? 'teal' : 'red'}"><b>${f1(b)}</b><span>${esc(T('u_mlmin', 'mL/min'))}</span></div>
          <div class="dv-sub">${NZA.rich(T('bl_tip', 'Gauze {6} — hold {LMB} on the bleeding point. Target under **%s**.', f1(cfg.bleedDone)))}</div></div>
          <div class="dv-bars one"><div class="vb"><span class="vl">${esc(T('dv_rate', 'Rate'))}</span><div class="vt"><i class="zn" style="height:${(cfg.bleedDone / top * 100).toFixed(1)}%"></i><i class="vf ${b <= cfg.bleedDone ? 'teal' : 'red'}" style="height:${(clamp(b / top, 0, 1) * 100).toFixed(1)}%"></i></div></div></div></div>`;
      }
      if (el.innerHTML !== html) el.innerHTML = html;
    },

    // world-anchored labels for located fragments
    renderTags() {
      const g = this.g, S = this.S;
      if (!g || !S) return;
      let html = '';
      for (const f of this.frags) {
        if (!f.found || f.out || this.finished) continue;
        const p = S.project(f.uv);
        if (!p.visible) continue;
        html += `<span class="bx-tag ${f.how === 'xray' ? 'x' : ''}" style="transform:translate(${(p.x * window.innerWidth).toFixed(0)}px,${(p.y * window.innerHeight).toFixed(0)}px)"><b>#${f.n}</b>${esc(T('tag_depth', '%s mm', Math.round(f.depth)))}</span>`;
      }
      if (this.tagsHtml !== html) { this.tagsHtml = html; this.tags.innerHTML = html; }
    },

    /* ═════════════ panel ═════════════ */
    buildPanel() {
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 8, tag: T('tag', 'Bullet extraction'), steps: STEPS.map(s => T(s.label[0], s.label[1])),
        title: '', text: '', stats: this.stats(), tools: this.toolList(), hints: this.hints(),
        abort: { label: T('hold_abort', 'Hold to abort'), key: 'ESC', seconds: 1.2 },
        onAbort: () => this.abort(),
        onTool: key => this.pickTool(key),
      });
      const body = this.pp.el.querySelector('.pp-body') || this.pp.el;
      const after = body.querySelector('.pp-text');
      this.dots = document.createElement('div'); this.dots.className = 'bx-dots';
      this.tip = document.createElement('div'); this.tip.className = 'bx-tip';
      if (after && after.nextSibling) { body.insertBefore(this.tip, after.nextSibling); body.insertBefore(this.dots, this.tip); }
      else { body.appendChild(this.dots); body.appendChild(this.tip); }
    },
    hints() {
      const g = this.g, out = [{ keys: ['RMB'], label: T('cam_look', 'Look') }, { keys: [T('key_wheel', 'Wheel')], label: T('cam_zoom', 'Zoom') }, { keys: ['R'], label: T('cam_recenter', 'Recentre') }];
      if (!g) return out;
      if (g.tool === 'scalpel') out.unshift({ keys: ['Q', 'E'], label: T('h_blade', 'Blade depth') });
      if (g.step >= 4 && g.step <= 6) out.unshift({ keys: [T('key_space', 'Space')], label: T('h_spread', 'Spread') });
      if (g.step === 5) {
        out.unshift({ keys: ['A', 'D'], label: T('h_rock', 'Rock free') });
        if (g.xt.out.length && this.remaining().length) out.unshift({ keys: ['L'], label: T('h_leave', 'Leave the rest') });
      }
      return out;
    },
    stats() {
      const inj = this.inj, left = this.frags ? this.remaining().length : (+inj.retained || 1);
      const b = this.g ? this.bleedNow() : +inj.bleed || 0;
      return [
        { id: 'site', label: T('st_site', 'Site'), value: inj.regionLabel || inj.region || '', small: true },
        { id: 'left', label: T('st_left', 'Retained'), value: String(left), unit: left === 1 ? T('u_frag', 'piece') : T('u_frags', 'pieces'), tone: left ? '' : 'teal' },
        { id: 'bleed', label: T('st_bleed', 'Bleed'), value: f1(b), unit: T('u_mlmin', 'mL/min'), tone: b >= 10 ? 'red' : b >= 3 ? 'amber' : '' },
      ];
    },
    toolList() {
      const g = this.g, d = this.d;
      return TOOLS.map(t => {
        const o = { key: t.key, label: T(t.label[0], t.label[1]), icon: t.icon };
        let state = '';
        if (g) {
          const cut = !!g.cut.w;
          switch (t.id) {
            case 'probe': if (g.done[3]) state = 'done'; break;
            case 'iodine': if (g.done[2] || g.skipped[2] || g.step > 2) state = g.done[2] ? 'done' : 'locked'; break;
            case 'scalpel': if (g.xt.out.length && !this.remaining().length || g.step > 5) state = 'done'; break;
            case 'suction': if (!cut || g.step >= 8) state = 'locked'; break;
            case 'forceps': if (g.step > 5 || (g.xt.out.length && !this.remaining().length)) state = 'done'; break;
            case 'gauze': o.count = String(Math.max(0, g.gz.have - g.gz.used + (g.gz.swab ? 1 : 0))); if (!g.gz.have || !cut || g.step >= 8) state = 'locked'; break;
            case 'driver': if (g.done[7]) state = 'done'; break;
            case 'xray': if (!d.film) { state = 'locked'; o.count = '0'; } else if (g.film.open) state = 'active'; break;
          }
          if (g.tool === t.id) state = 'active';
          if (t.id === 'xray' && d.film && g.film.open) state = 'active';
        }
        o.state = state;
        return o;
      });
    },
    refreshTools() { if (this.pp) this.pp.set({ tools: this.toolList(), hints: this.hints() }); },
    setTip(text, tone = '') {
      if (!this.tip) return;
      this.tip.className = `bx-tip ${tone}`;
      this.tip.innerHTML = text ? `<span>${NZA.rich(text)}</span>` : '';
    },
    flash(type, text, ms) { if (this.pp) this.pp.flash(type, text, ms); },

    updatePanel() {
      const g = this.g, pp = this.pp, cfg = this.cfg;
      if (!g || !pp) return;
      pp.set({ stats: this.stats() });
      let wide;
      const N = this.frags.length;
      switch (g.step) {
        case 1: {
          const n = this.frags.filter(f => f.found).length;
          wide = { label: T('w_located', 'Located'), value: String(n), unit: `/${N}`, tone: n === N ? 'teal' : '', meter: { value: n / N, segs: true },
            caption: this.d.film ? T('w_located_cap', 'Probe the wound track, or read the film {X}') : T('w_located_cap2', 'Probe the wound track to find the metal') };
          break;
        }
        case 2: {
          const c = pct(g.io.cov);
          wide = { label: T('w_cover', 'Prep coverage'), value: String(c), unit: '%', tone: c >= 97 ? 'teal' : '', meter: { value: g.io.cov, zone: [cfg.prepDone, 1] },
            caption: T('w_cover_cap', 'Scrub the whole ring, centre → out') };
          break;
        }
        case 3: {
          const c = g.cut, L = c.w ? c.w.length / MM : 0;
          wide = { label: T('w_cut', 'Incision'), value: String(Math.round(L)), unit: 'mm', tone: L > c.ideal * 1.3 ? 'amber' : '',
            meter: { value: clamp(L / (c.ideal * 1.6), 0, 1), zone: [c.ideal * 0.85 / (c.ideal * 1.6), c.ideal * 1.25 / (c.ideal * 1.6)] },
            caption: T('w_cut_cap', 'Over the fragment · about %s mm', Math.round(c.ideal)) };
          break;
        }
        case 4: {
          const v = this.exposure();
          wide = { label: T('w_expose', 'Exposure'), value: String(pct(v)), unit: '%', tone: v >= 1 ? 'teal' : '', meter: { value: v },
            caption: g.ex.spread < cfg.exposeSpread ? T('w_expose_spread', 'Hold {Space} to spread the edges') : T('w_expose_clear', 'Clear the blood off the fragment') };
          break;
        }
        case 5: {
          const f = g.xt.grip, out = g.xt.out.length;
          wide = { label: T('w_extract', 'Fragment %s', Math.min(N, out + 1)), value: String(pct(f ? f.prog : 0)), unit: '%', tone: f ? 'teal' : '',
            meter: { value: f ? f.prog : 0 },
            caption: f ? (f.lodge > 0 ? T('gr_lodged', 'Lodged — rock it free: {A} {D}') : T('w_extract_pull', 'Slow and steady — watch the traction')) : T('w_extract_cap', '%s of %s out', out, N),
            captionTone: f && g.xt.speed > cfg.pullSafe ? 'amber' : '' };
          break;
        }
        case 6: {
          const b = this.bleedNow();
          wide = { label: T('w_bleed', 'Bleed'), value: f1(b), unit: T('u_mlmin', 'mL/min'), tone: b <= cfg.bleedDone ? 'teal' : b > 6 ? 'red' : 'amber',
            meter: { value: clamp(1 - b / Math.max(g.hm.start, cfg.bleedDone * 2), 0, 1), tone: b <= cfg.bleedDone ? '' : 'amber' },
            caption: T('w_bleed_cap', 'Press on the bleeding point · under %s', f1(cfg.bleedDone)) };
          break;
        }
        case 7: {
          const n = this.coveredSlots().filter(Boolean).length;
          wide = { label: T('w_section', 'Section'), value: String(Math.min(n + (g.done[7] ? 0 : 1), g.sut.N)), unit: `/${g.sut.N}`, tone: 'teal',
            meter: { value: g.sut.N ? n / g.sut.N : 0, segs: true },
            caption: g.sut.last ? g.sut.last[1] : T('w_section_cap', 'Bite %s mm each side · straight across', cfg.bite), captionTone: g.sut.last ? (g.sut.last[0] === 'ok' ? 'teal' : 'amber') : '' };
          break;
        }
        case 8: {
          const D = g.dr.D, s = D ? D.stuck : 0;
          wide = { label: T('w_stuck', 'Dressing stuck'), value: String(pct(s)), unit: '%', tone: s >= 0.9 ? 'teal' : '', meter: { value: s, zone: [cfg.stuckDone, 1] },
            caption: D && D.state !== 'rest' && D.state !== 'carried' ? T('w_cover_d', 'Covers %s% of the wound', pct(g.dr.cover)) : T('w_stuck_cap', 'Lay it over the wound, then rub it down'),
            captionTone: D && D.state === 'placed' && g.dr.cover < cfg.coverMin ? 'amber' : '' };
          break;
        }
      }
      if (wide) pp.set({ wide });
    },

    /* ═════════════ steps ═════════════ */
    texts(n) {
      const film = !!this.d.film;
      return {
        1: [T('s1_title', 'Locate the fragment'), film ? T('s1_text', 'Press the probe into the wound and feel for it — follow the track until it clicks on metal. Or press {X} to read the film.') : T('s1_text_nofilm', 'Press the probe into the wound and feel for it — follow the track until it clicks on metal.')],
        2: [T('s2_title', 'Disinfect the site'), T('s2_text', 'Iodine swab — hold {LMB} and scrub in circles from the incision site outward until the ring is fully covered.')],
        3: [T('s3_title', 'Incise over the fragment'), T('s3_text', 'Set the blade with {Q} / {E}, then hold {LMB} and draw a straight cut over the marked fragment.')],
        4: [T('s4_title', 'Expose the fragment'), T('s4_text', 'Hold {Space} to spread the edges, then suction {4} and blot {6} until you can see the metal.')],
        5: [T('s5_title', 'Extract the projectile'), T('s5_text', 'Forceps — click the fragment to grip it, then draw the mouse back **slowly** to work it free.')],
        6: [T('s6_title', 'Control the bleeding'), T('s6_text', 'Gauze — hold {LMB} on the bleeding point and keep the pressure on until the bleed is under the limit.')],
        7: [T('s7_title', 'Suture the incision'), T('s7_text', 'Press on the near edge at the marker, pull across to the far edge, release to tie the stitch.')],
        8: [T('s8_title', 'Apply the dressing'), T('s8_text', 'Pick the dressing up by its edge, lay it over the wound and the entry hole, then rub it down.')],
      }[n];
    },
    enterStep(n, first) {
      const g = this.g, S = this.S;
      g.step = n;
      const tx = this.texts(n);
      this.pp.set({ step: n, title: tx[0], titleTone: '', text: tx[1] });
      this.useTool(MAIN[n]);
      S.markers.remove('prep');
      S.markers.remove('in'); S.markers.remove('inR'); S.markers.remove('out');
      if (n === 1) this.frame0();
      if (n === 2) this.startPrep();
      if (n === 3) this.frameOn(this.cutCentre(), Math.max(g.cut.ideal * 3.2 * MM, this.R0 * 1.6));
      if (n === 4) this.frameOn(this.cutCentre(), Math.max((g.cut.L || g.cut.ideal) * 2.6 * MM, 0.05));
      if (n === 6) { g.hm.start = Math.max(this.bleedNow(), this.cfg.bleedDone * 1.5); }
      if (n === 7) this.startSuture();
      if (n === 8) this.startDressing();
      this.dots.style.display = n === 7 ? '' : 'none';
      this.markFrags();
      this.stepTip();
      this.updatePanel();
      this.renderPlan(true);
      this.renderNotes();
      if (!first) this.snd('success');
    },
    completeStep(n, msg) {
      const g = this.g;
      if (g.done[n]) return;
      g.done[n] = true;
      if (msg) this.flash('ok', msg, 2400);
      this.renderPlan(true);
      if (n === 8) { this.finish(); return; }
      clearTimeout(this.stepTimer);
      this.stepTimer = setTimeout(() => { if (this.g === g && this.alive && g.step === n && !this.finished) this.enterStep(n + 1); }, 750);
    },
    skipTo(n) {
      const g = this.g;
      for (let k = g.step; k < n; k++) if (!g.done[k]) g.skipped[k] = true;
      this.stopActions();
      clearTimeout(this.stepTimer);
      this.enterStep(n);
    },
    confirmSkip(key, n, what) {
      const now = performance.now();
      if (this.skipArm && this.skipArm.key === key && now - this.skipArm.t < 2800) { this.skipArm = null; this.skipTo(n); return; }
      this.skipArm = { key, t: now };
      this.flash('warn', T('skip_confirm', 'Skip ahead? %s — press {%s} again.', what, key), 2800);
    },
    pickTool(key) {
      const g = this.g;
      if (!g || this.finished) return;
      const t = TOOLS.find(x => x.key === String(key).toUpperCase());
      if (!t) return;
      const cut = !!g.cut.w;
      switch (t.id) {
        case 'xray': return this.toggleFilm();
        case 'probe':
          if (g.done[3]) return this.flash('warn', T('probe_late', 'The cut is open — you can see the fragment now.'));
          return this.useTool('probe');
        case 'iodine':
          if (g.step === 2) return this.useTool('iodine');
          if (g.step === 1) return this.confirmSkip(key, 2, T('skip_locate', 'the fragment is not located yet'));
          return this.flash('warn', T('tool_past', 'That step is behind you.'));
        case 'scalpel':
          if (g.step >= 3 && g.step <= 5) {
            if (g.step === 5 && g.xt.out.length && !this.remaining().length) return this.flash('warn', T('cut_late', 'No more cutting — the fragments are out.'));
            return this.useTool('scalpel');
          }
          if (g.step < 3) return this.confirmSkip(key, 3, g.step === 1 ? T('skip_both', 'not located and not disinfected') : T('skip_prep', 'the skin is not disinfected'));
          return this.flash('warn', T('tool_past', 'That step is behind you.'));
        case 'suction': case 'gauze': {
          if (!cut) return this.flash('warn', T('util_early', 'Nothing to clear yet — make the incision first.'));
          if (g.step >= 8) return this.flash('warn', T('util_late', 'The wound is closed.'));
          if (t.id === 'gauze' && !g.gz.have) return this.flash('bad', T('gauze_none', 'You carry no gauze.'));
          if (g.tool === t.id && MAIN[g.step] !== t.id) return this.useTool(MAIN[g.step]);
          return this.useTool(t.id);
        }
        case 'forceps':
          if (g.step === 5) return this.useTool('forceps');
          if (g.step === 4) {
            if (this.exposure() >= 1) { this.completeStep(4, T('s4_done', 'Fragment exposed.')); return; }
            return this.flash('warn', T('need_expose', 'You cannot see it yet — spread {Space} and suction {4} first.'));
          }
          if (g.step < 4) return this.flash('warn', T('need_cut', 'Cut down to it first.'));
          return this.flash('warn', T('tool_past', 'That step is behind you.'));
        case 'driver':
          if (g.step === 7) return this.useTool('driver');
          if (g.step === 6) return this.confirmSkip(key, 7, T('skip_bleed', 'still bleeding %s mL/min', f1(this.bleedNow())));
          if (g.step === 5 && g.xt.out.length && this.remaining().length) return this.flash('warn', T('leave_hint', 'Press {L} to leave the remaining fragments in.'));
          if (g.step < 6) return this.flash('warn', T('need_extract', 'Get the fragment out first.'));
          return this.flash('warn', T('tool_past', 'That step is behind you.'));
        case 'dressing':
          if (g.step === 8) return this.useTool('dressing');
          if (g.step === 7) return this.confirmSkip(key, 8, T('skip_suture', 'the incision stays open'));
          return this.flash('warn', T('need_close', 'Close the wound first.'));
      }
      return undefined;
    },
    useTool(id) {
      const g = this.g, S = this.S;
      if (!g || !S) return;
      this.stopActions();
      g.tool = id;
      let tool = null;
      if (ENGINE[id]) tool = S.tools.use(ENGINE[id]);
      else if (id === 'iodine') tool = S.tools.use(this.tl.swab);
      else if (id === 'suction') tool = S.tools.use(this.tl.suction);
      else if (id === 'forceps') tool = S.tools.use(this.tl.forceps);
      else S.tools.use(null);
      if (tool && tool.base) Object.assign(tool.pose, tool.base);
      if (id === 'probe' && tool) Object.assign(tool.pose, { pressLift: -0.002, tilt: 0.45, yaw: 1.4 });
      if (id === 'iodine') this.tl.swab.set({ load: g.io.load });
      if (id === 'forceps') this.tl.forceps.set({ open: 0.75 });
      S.tools.follow = true;
      this.refreshTools();
      this.stepTip();
      this.renderDev();
    },
    stopActions() {
      const g = this.g, S = this.S;
      if (!g || !S) return;
      if (g.pr.on) this.stopProbe();
      if (g.cut.drawing) this.endCut();
      if (g.xt.grip) this.releaseGrip(false);
      if (g.sut.drag) this.cancelDrag();
      S.tools.press(false);
      if (this.tl) this.tl.suction.set({ flow: 0 });
    },
    stepTip() {
      const g = this.g;
      if (!g) return;
      if (g.tool === 'gauze' && g.step !== 6) return this.setTip(T('tip_gauze', 'Hold {LMB} to blot the blood. Press {6} again to put the gauze down.'));
      if (g.tool === 'suction' && g.step !== 4) return this.setTip(T('tip_suction', 'Hold {LMB} over pooled blood to suck it away. Press {4} again to put it down.'));
      switch (g.step) {
        case 1: return this.setTip(this.d.film ? T('tip_1', 'Start **in the entry wound**. If it resists, steer the mouse along the arrow — pushing against tissue makes a false passage.') : T('tip_1b', 'Start **in the entry wound** and follow the track. Shallow pieces can also be felt by pressing on the skin around it.'));
        case 2: return this.setTip(T('tip_2', 'Begin over the fragment mark, spiral outward and do not come back over the centre.'));
        case 3: return this.setTip(T('tip_3', 'Through skin and fat only — about **%s mm** deep here. Start at an end to lengthen the cut.', Math.round(this.band()[1])), '');
        case 4: return this.setTip(T('tip_4', 'Do not over-spread: past the green band the tissue tears.'), 'amber');
        case 5: return this.setTip(T('tip_5', 'If the traction bar turns amber, slow down. Red = it slips and tears the tissue.'), 'amber');
        case 6: return this.setTip(T('tip_6', 'Clear the field with suction {4} to see where it bleeds from, then press there.'));
        case 7: return this.setTip(T('tip_7', 'Bite about **%s mm** from the edge on both sides and pull straight across.', this.cfg.bite));
        case 8: return this.setTip(T('tip_8', 'Grab the dressing by an **edge**, cover the incision and the entry hole, rub from the centre out.'));
      }
      return this.setTip('');
    },

    /* ═════════════ geometry helpers ═════════════ */
    remaining() { return this.frags.filter(f => !f.out); },
    inWindow(uv) { return this.S.distanceUv(uv, [0.5, 0.5]) <= this.R0 - 0.0012; },
    mmFromEntry(uv) { const p = this.S.uvToST(uv); return [p[0] / MM, p[1] / MM]; },
    nearestUnfound(uv) {
      let best = null, bd = Infinity;
      for (const f of this.frags) { if (f.found || f.out) continue; const d = this.S.distanceUv(uv, f.uv); if (d < bd) { bd = d; best = f; } }
      return best;
    },
    fragCentroid(list) {
      const l = (list || this.frags).filter(f => !f.out);
      if (!l.length) return this.entryUv.slice();
      let x = 0, y = 0; l.forEach(f => { x += f.x; y += f.y; });
      return this.S.stToUv(x / l.length * MM, y / l.length * MM);
    },
    idealCut() {
      const fr = this.frags;
      let spread = 0, maxSize = 0, depth = 0;
      fr.forEach((a, i) => { maxSize = Math.max(maxSize, a.size); depth += a.depth; fr.forEach((b, j) => { if (j > i) spread = Math.max(spread, Math.hypot(a.x - b.x, a.y - b.y)); }); });
      return clamp(spread + maxSize * 1.25 + (depth / fr.length) * 0.3, 14, 42);
    },
    band() { return [Math.max(2, Math.round(this.fat * 0.6)), this.fat + 2]; },
    cutCentre() {
      const c = this.g && this.g.cut;
      if (c && c.w) return c.w.at(0.5).uv;
      const found = this.frags.filter(f => f.found && !f.out);
      return this.fragCentroid(found.length ? found : null);
    },
    frame0() { this.S.controls.frame([0.5, 0.5], this.R0 * 2.7, { instant: false }); },
    frameOn(uv, width) { this.S.controls.frame(uv, clamp(width, 0.04, this.R0 * 3), { instant: false }); },
    underCut(f) {
      const w = this.g.cut.w;
      if (!w) return false;
      const loc = w.locate(f.uv);
      return loc.d / MM <= this.cfg.coverTol && loc.tN > 0.05 && loc.tN < 0.95;
    },
    gapeNow() {
      const g = this.g;
      if (g.step >= 7) return 2.4;
      const L = g.cut.L || (g.cut.w ? g.cut.w.length / MM : 20);
      return lerp(1.8, clamp(L * 0.42, 7, 14), clamp(g.ex.spread, 0, 1.25));
    },
    depthVis() {
      const g = this.g;
      const base = clamp(g.cut.blade * 0.75, 3, 8);
      if (g.step >= 7) return Math.min(base, 5);
      return lerp(base, 10, clamp(g.ex.spread, 0, 1));
    },
    fieldClear() {
      const rem = this.remaining().filter(f => this.underCut(f));
      if (!rem.length) return 1;
      let worst = 0;
      rem.forEach(f => { worst = Math.max(worst, this.S.layers.average('blood', f.uv, 3 * MM)); });
      return clamp(1 - worst, 0, 1);
    },
    exposure() {
      const g = this.g, cfg = this.cfg;
      const s = clamp(g.ex.spread / cfg.exposeSpread, 0, 1), c = clamp(this.fieldClear() / (1 - cfg.exposeBlood), 0, 1);
      if (!this.remaining().every(f => this.underCut(f))) return Math.min(0.5, s * c);
      return s * 0.5 + (s >= 1 ? c * 0.5 : 0);
    },
    bleederUv() {
      const g = this.g, outs = this.frags.filter(f => f.out);
      if (outs.length) return outs[outs.length - 1].uv;
      return g.cut.w ? g.cut.w.at(0.5).uv : this.entryUv;
    },

    /* ═════════════ bleeding & blood loss ═════════════ */
    bleedNow() {
      const g = this.g;
      if (!g) return +(this.inj && this.inj.bleed) || 0;
      if (!g.cut.w) return Math.max(0, (+this.inj.bleed || 0) * 0.3);
      let b = g.bl.rate + g.bl.boost;
      if (g.sut.list.length) b *= 1 - 0.9 * this.closedFrac();
      if (g.done[8] || (g.dr.D && g.dr.D.stuck > 0.5)) b *= 0.4;
      return Math.max(0, b);
    },
    addLoss(ml, why) {
      const g = this.g;
      g.loss += ml;
      if (why) g.lossEv.push([why, Math.round(ml)]);
    },
    setBleed() {
      const S = this.S, g = this.g;
      if (!S) return;
      if (g && g.cut.w) {
        S.fluids.bleed(this.entry, 0);
        const b = this.bleedNow();
        S.fluids.bleed(g.cut.w, b > 0.1 && g.step < 8 ? clamp(b * 0.5, 0.4, 9) : 0);
      } else {
        const b = (+this.inj.bleed || 0) * 0.3;
        S.fluids.bleed(this.entry, b > 0.2 ? clamp(b, 0.4, 4) : 0);
      }
    },
    tickBleeding(dt) {
      const g = this.g, S = this.S, c = g.cut;
      g.bl.boost *= Math.exp(-dt / 6);
      if (!c.w) return;
      g.bl.rate = Math.max(0.15, g.bl.rate * Math.exp(-0.003 * dt));
      const b = this.bleedNow();
      if (!g.done[8]) g.loss += b / 60 * dt;
      // the cut keeps filling with blood while it is open
      g.poolT -= dt;
      if (g.poolT <= 0 && g.step < 8) {
        g.poolT = 0.1;
        const amt = clamp(b * this.cfg.poolRate * (g.step >= 7 ? 1 - this.closedFrac() : 1), 0, 0.14);
        if (amt > 0.003) {
          for (let k = 0; k < 2; k++) {
            const tN = 0.08 + Math.random() * 0.84, at = c.w.at(tN), hg = c.w.halfGape(tN) + 0.0005;
            S.layers.paint('blood', at.uv, [hg * 1.1, hg * 1.1], amt, { hardness: 0.3, angle: Math.atan2(at.dir[1], at.dir[0]) });
          }
          if (this.frags.some(f => f.out) && g.step <= 6) S.layers.paint('blood', this.bleederUv(), 2.2 * MM, amt * 1.4, { hardness: 0.35 });
        }
      }
      g.flowT -= dt;
      if (g.flowT <= 0) { g.flowT = 0.5; this.setBleed(); }
    },

    /* ═════════════ pain & flinches ═════════════ */
    updatePain(dt) {
      const g = this.g;
      g.painSpike *= Math.exp(-dt * 1.1);
      g.pain = clamp(g.pain0 + g.painSpike, 0, 100);
    },
    hurt(amount, chance) {
      const g = this.g;
      if (g.pain0 <= 0) return false;
      const numb = this.d.patient && this.d.patient.numb ? 0.7 : 0;
      g.painSpike = Math.min(60, g.painSpike + amount * (1 - numb));
      g.pain = clamp(g.pain0 + g.painSpike, 0, 100);
      if (chance && g.pain >= this.cfg.flinchPain && Math.random() < chance * (1 - numb)) { this.flinch(); return true; }
      return false;
    },
    flinch() {
      const g = this.g;
      g.flinches++;
      this.S.controls.shake(0.8, 480);
      if (g.t - g.lastSay > 3.4) {
        g.lastSay = g.t;
        const line = SAY[Math.floor(Math.random() * SAY.length)];
        NZA.speech({ name: (this.d.patient && this.d.patient.name) || T('patient', 'Patient'), text: T(line[0], line[1]), ms: 2400 });
      }
      NZA.post('bullet:flinch', { pain: Math.round(g.pain) });
      this.snd('tone', 180, 120, { vol: 0.05, type: 'triangle' });
      return true;
    },

    /* ═════════════ input ═════════════ */
    down(e) {
      const g = this.g;
      if (!g || this.finished || e.button !== 0) return;
      g.lmb = true;
      const S = this.S;
      switch (g.tool) {
        case 'probe': this.startProbe(); break;
        case 'iodine': g.io.last = null; S.tools.press(true); break;
        case 'scalpel': this.startCut(); break;
        case 'suction': S.tools.press(true); break;
        case 'forceps': this.grab(); break;
        case 'gauze': S.tools.press(true); break;
        case 'driver': this.startStitch(); break;
        case 'dressing': this.dressDown(); break;
      }
    },
    up(e) {
      const g = this.g;
      if (!g || e.button !== 0) return;
      g.lmb = false;
      const S = this.S;
      if (g.tool === 'probe') this.stopProbe();
      if (g.tool === 'scalpel' && g.cut.drawing) this.endCut();
      if (g.tool === 'forceps' && g.xt.grip) this.releaseGrip(true);
      if (g.tool === 'driver' && g.sut.drag) this.endStitch();
      if (g.tool === 'dressing') this.dressUp();
      if (g.tool === 'iodine') g.io.last = null;
      if (S) { S.tools.press(false); this.tl.suction.set({ flow: 0 }); }
    },
    spreadKey(on) {
      const g = this.g;
      if (!g || this.finished) return;
      if (on) {
        if (!g.cut.w || g.step < 4) return this.flash('warn', T('spread_early', 'Make the incision first.'));
        if (g.step >= 7) return this.flash('warn', T('spread_late', 'The retractor is out — you are closing now.'));
        if (g.xt.grip) return;
      }
      g.ex.space = !!on;
      if (!on) g.ex.overT = 0;
    },
    blade(dir) {
      const g = this.g, cfg = this.cfg;
      if (!g || g.tool !== 'scalpel' || g.cut.drawing) return;
      g.cut.blade = clamp(g.cut.blade + dir, cfg.bladeMin, cfg.bladeMax);
      this.snd('tick');
      this.renderDev();
    },

    /* ═════════════ frame ═════════════ */
    frame(dt) {
      const g = this.g;
      if (!g || !this.alive) return;
      g.t += dt;
      this.updatePain(dt);
      switch (g.tool) {
        case 'probe': this.tickProbe(dt); break;
        case 'iodine': this.tickSwab(dt); break;
        case 'scalpel': this.tickCut(dt); break;
        case 'suction': this.tickSuction(dt); break;
        case 'forceps': this.tickForceps(dt); break;
        case 'gauze': this.tickGauze(dt); break;
        case 'driver': this.tickStitch(dt); break;
        case 'dressing': this.tickDressing(dt); break;
      }
      this.tickSpread(dt);
      this.tickBleeding(dt);
      this.placeFrags(dt);
      this.checkProgress(dt);
      this.renderTags();
      this.updateCursor();
      g.uiT -= dt;
      if (g.uiT <= 0) { g.uiT = 0.1; this.updatePanel(); this.renderPlan(); this.renderDev(); this.renderStrip(); }
    },
    checkProgress() {
      const g = this.g, cfg = this.cfg;
      if (this.finished) return;
      if (g.step === 2 && g.io.mask && !g.done[2]) {
        g.io.cov = g.io.mask.coverage('iodine', 0.3);
        if (g.io.cov >= cfg.prepDone) { g.io.cov = 1; this.completeStep(2, T('s2_done', 'Site prepped — the field is sterile.')); }
      }
      if (g.step === 4 && !g.done[4] && this.exposure() >= 1) {
        this.remaining().forEach(f => { f.exposed = true; });
        this.completeStep(4, T('s4_done_n', 'Exposed — there it is. Grip it with the forceps {5}.'));
      }
      if (g.step === 6 && !g.done[6] && this.bleedNow() <= cfg.bleedDone) this.completeStep(6, T('s6_done', 'Bleeding controlled — %s mL/min.', f1(this.bleedNow())));
    },

    /* ═════════════ fragments in the scene ═════════════ */
    markFrags() {
      const g = this.g, S = this.S;
      if (!S) return;
      for (const f of this.frags) {
        const id = `fr_${f.id}`;
        if (f.out || !f.found || g.step >= 6) { S.markers.remove(id); continue; }
        if (g.step >= 4 && this.underCut(f)) {
          S.markers.set(id, { uv: f.uv, kind: 'ring', size: (f.size + 5) * MM, color: 0x0fd4c4, pulse: g.step === 5, opacity: 0.9 });
        } else if (f.how === 'xray') {
          S.markers.set(id, { uv: f.uv, kind: 'dashed', size: (f.size + (this.d.film && this.d.film.quality === 'motion' ? 10 : 5)) * MM, color: 0xffffff, pulse: false, opacity: 0.85 });
        } else {
          S.markers.set(id, { uv: f.uv, kind: 'cross', size: 0.0055, color: 0xffffff, pulse: false, opacity: 0.9 });
        }
      }
    },
    placeFrags(dt) {
      const g = this.g, S = this.S;
      const reveal = smooth(0.3, 0.85, g.ex.spread);
      for (const f of this.frags) {
        const m = f.mesh;
        if (!m) continue;
        const fly = f.flyT !== undefined;
        if (fly) {
          f.flyT += dt;
          const k = clamp(f.flyT / 0.65, 0, 1);
          m.position.lerpVectors(f.flyFrom, f.flyTo, k);
          m.position.addScaledVector(f.flyUp, Math.sin(k * Math.PI) * 0.02);
          m.rotation.x += dt * 6;
          if (k >= 1) { m.visible = false; delete f.flyT; if (!f.clinked) { f.clinked = true; this.snd('tone', 2400, 50, { vol: 0.05, type: 'triangle' }); this.snd('tone', 3700, 80, { vol: 0.035, type: 'triangle', at: 0.04 }); } }
          continue;
        }
        if (f.out) { m.visible = false; continue; }
        const under = g.cut.w && this.underCut(f);
        if (!under || g.ex.spread < 0.3 || g.step >= 7) { m.visible = false; continue; }
        m.visible = true;
        // blood film over it
        const cov = S.layers.average('blood', f.uv, 2.6 * MM);
        f.tint = lerp(f.tint, clamp(cov * 1.3, 0, 0.92), 1 - Math.exp(-dt * 6));
        m.material.color.setRGB(1, 1, 1).lerp(this.fragBlood, f.tint);
        if (g.xt.grip === f && S.tools.active) {
          const tip = S.tools.active.tipWorld();
          const ax = this._w.set(0, 1, 0).applyQuaternion(S.tools.active.group.quaternion);
          m.position.copy(tip).addScaledVector(ax, -m.userData.thick * 0.35);
          continue;
        }
        // resting in the cavity: nudged toward the centre line of the cut so the walls do not swallow it
        const loc = g.cut.w.locate(f.uv), at = g.cut.w.at(loc.tN);
        const p0 = S.uvToST(f.uv), off = clamp(loc.d, 0, g.cut.w.halfGape(loc.tN) * 0.45);
        const dx = p0[0] - at.s, dy = p0[1] - at.t, dl = Math.hypot(dx, dy) || 1;
        const disp = S.stToUv(at.s + dx / dl * off, at.t + dy / dl * off);
        const sp = S.surfaceAt(disp);
        const rise = f.prog * 0.006;
        m.position.copy(sp.point).addScaledVector(sp.normal, -m.userData.thick * lerp(0.62, 0.22, reveal) + rise);
        // lie along its angle in the tangent plane
        const st = S.uvToST(disp), e = 0.002;
        const q = S.surfaceAt(S.stToUv(st[0] + Math.cos(f.rot) * e, st[1] + Math.sin(f.rot) * e)).point;
        const tY = this._v.copy(q).sub(sp.point).normalize();
        const N = sp.normal.clone().normalize();
        const X = new (T3().Vector3)().crossVectors(tY, N).normalize();
        const Y = new (T3().Vector3)().crossVectors(N, X).normalize();
        const M = new (T3().Matrix4)().makeBasis(X, Y, N);
        m.quaternion.setFromRotationMatrix(M);
      }
    },

    /* ═════════════ 1 · LOCATE (probe) ═════════════ */
    startProbe() {
      const g = this.g, S = this.S, hit = S.tools.hit, cfg = this.cfg;
      if (!hit) return;
      if (g.done[3]) return this.flash('warn', T('probe_late', 'The cut is open — you can see the fragment now.'));
      if (!this.inWindow(hit.uv)) return this.flash('warn', T('off_window', 'Work inside the drape window.'));
      const pr = g.pr;
      const dE = S.distanceUv(hit.uv, this.entryUv) / MM;
      Object.assign(pr, { on: true, depth: 0, start: hit.uv.slice(), blocked: false, contact: null, palped: false, bone: false, err: 0, steer: null });
      pr.track = dE <= cfg.trackRadius;
      pr.target = pr.track ? this.nearestUnfound(this.entryUv) : null;
      S.tools.press(true);
      if (pr.track) this.hurt(10, cfg.flinchChance * 0.5); else this.hurt(4, 0);
    },
    stopProbe() {
      const g = this.g;
      g.pr.on = false;
      this.S.tools.press(false);
    },
    tickProbe(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, pr = g.pr, tool = S.tools.active, hit = S.tools.hit;
      if (!pr.on || !g.lmb || !hit) {
        pr.depth = Math.max(0, pr.depth - 45 * dt);
        if (pr.depth <= 0) { pr.contact = null; pr.bone = false; }
        if (tool) { tool.pose.pressLift = -0.002; tool.pose.tilt = lerp(tool.pose.tilt, 0.45, 1 - Math.exp(-dt * 6)); }
        return;
      }
      if (pr.track) {
        const f = pr.target;
        const goal = f ? f.depth : this.boneDepth;
        const k = f ? clamp(pr.depth / f.depth, 0, 1) : 0;
        const want = f ? [f.x * k, f.y * k] : [0, 0];
        const cur = this.mmFromEntry(hit.uv);
        pr.err = Math.hypot(cur[0] - want[0], cur[1] - want[1]);
        // where the track goes next: the arrow points from the cursor toward the next bit of track
        const k2 = f ? clamp((pr.depth + 3) / f.depth, 0, 1) : 0;
        const nx = f ? f.x * k2 - cur[0] : -cur[0], ny = f ? f.y * k2 - cur[1] : -cur[1];
        pr.steer = Math.atan2(ny, nx);
        if (!pr.blocked && !pr.contact && !pr.bone) {
          if (pr.err > cfg.steerFail) {
            pr.blocked = true; pr.falses++;
            this.addLoss(3, 'false');
            S.layers.paint('blood', hit.uv, 1.4 * MM, 0.45, { hardness: 0.4 });
            this.hurt(16, cfg.flinchChance);
            this.flash('bad', T('pr_false', 'False passage — you pushed out of the track. Release and start again in the wound.'), 3200);
            this.snd('fail');
          } else {
            const slow = pr.err <= cfg.steerTol ? 1 : lerp(1, cfg.probeSlow, (pr.err - cfg.steerTol) / (cfg.steerFail - cfg.steerTol));
            const near = f && f.depth - pr.depth < 4 ? 0.55 : 1;
            pr.depth = Math.min(goal, pr.depth + cfg.probeSpeed * slow * near * dt);
            if (f && pr.depth >= f.depth - 0.05) this.probeContact(f);
            else if (!f && pr.depth >= this.boneDepth - 0.05) { pr.bone = true; this.snd('tone', 240, 60, { vol: 0.05, type: 'triangle' }); this.flash('warn', T('pr_bone', 'Bone at %s mm — no more metal in this track.', Math.round(pr.depth))); }
          }
        }
        if (pr.err > cfg.steerTol && !pr.blocked && !pr.contact) this.cursorHint(T('cur_resist', 'Resistance — steer'), 'amber');
        if (tool) {
          const want2 = f ? [f.x, f.y] : [0, 0], lat = Math.hypot(want2[0], want2[1]);
          if (lat > 0.3 && f) { tool.pose.yaw = Math.atan2(want2[1], -want2[0]); tool.pose.tilt = clamp(Math.atan2(lat, f.depth) + 0.25, 0.25, 0.95); }
          tool.pose.pressLift = -Math.min(pr.depth, 14) * MM * 0.55;
        }
      } else {
        // intact skin: the probe only dimples it, but a shallow piece can be felt
        pr.depth = Math.min(2.5, pr.depth + 6 * dt);
        if (tool) tool.pose.pressLift = -0.0018;
        if (pr.depth >= 2.4 && !pr.palped) {
          pr.palped = true;
          const f = this.frags.find(x => !x.found && !x.out && x.depth <= cfg.palpateDepth && S.distanceUv(hit.uv, x.uv) / MM <= x.size / 2 + cfg.palpateTol);
          if (f) {
            this.locate(f, 'palpate');
            pr.contact = f;
            this.flash('ok', T('pr_palp', 'You can feel it under the skin — %s mm deep.', Math.round(f.depth)), 2600);
          }
        }
      }
      this.cursorProgress(clamp(pr.depth / Math.max(4, (pr.target ? pr.target.depth : this.boneDepth)), 0, 1), '');
    },
    probeContact(f) {
      const g = this.g, pr = g.pr;
      pr.contact = f;
      pr.depth = f.depth;
      this.locate(f, 'probe');
      this.snd('tone', 2900, 55, { vol: 0.06 }); this.snd('tone', 4200, 90, { vol: 0.04, at: 0.035 });
      this.hurt(8, this.cfg.flinchChance * 0.4);
      const left = this.frags.filter(x => !x.found && !x.out).length;
      this.flash('ok', left ? T('pr_metal_more', 'Metal at %s mm — fragment %s located. %s more to find.', Math.round(f.depth), f.n, left) : T('pr_metal', 'Metal at %s mm — fragment located.', Math.round(f.depth)), 2600);
    },
    locate(f, how) {
      const g = this.g;
      if (f.found) return;
      f.found = true; f.how = how;
      this.markFrags();
      if (this.frags.every(x => x.found || x.out) && g.step === 1) this.completeStep(1, '');
      this.renderPlan(true);
    },

    /* X-ray film overlay */
    toggleFilm() {
      const g = this.g, d = this.d;
      if (!d.film) return this.flash('bad', T('film_none', 'No X-ray film of this region in your pockets — take one and read it, or use the probe.'), 3200);
      g.film.open = !g.film.open;
      this.filmEl.classList.toggle('on', g.film.open);
      if (g.film.open) {
        this.renderFilm();
        if (!g.film.used) {
          g.film.used = true;
          this.frags.forEach(f => { if (!f.found && !f.out) { f.found = true; f.how = 'xray'; } });
          this.markFrags();
          this.snd('tone', 900, 60, { vol: 0.04 });
          if (g.step === 1) this.completeStep(1, T('film_done', 'Read the film — %s fragment(s) marked on the skin.', this.frags.length));
        }
      }
      this.refreshTools();
      this.renderDev();
    },
    renderFilm() {
      const d = this.d, film = d.film, inj = this.inj;
      const motion = film.quality === 'motion';
      this.filmEl.innerHTML = `
        <div class="fh"><span class="nza-label">${esc(T('film_title', 'X-ray film'))}</span><span class="id">${esc(film.id || '')}</span><kbd>X</kbd></div>
        <div class="fv"><canvas></canvas></div>
        <div class="fm"><span>${esc(film.viewLabel || inj.regionLabel || '')} · ${esc(T('film_ap', 'AP + LAT'))}</span><span>${esc(film.taken || '')}</span></div>
        <div class="ff">${motion ? `<span class="bx-chip amber">${icon('alert')}${esc(T('film_motion', 'Motion blur — marks are approximate'))}</span>` : `<span class="bx-chip ${film.marked ? 'teal' : ''}">${icon(film.marked ? 'check' : 'xray')}${esc(film.marked ? T('film_read', 'Read on a lightbox') : T('film_unread', 'Not reported'))}</span>`}
          <span class="bx-chip">${icon('crosshair')}${esc(T('film_n', '%s metal fragment(s)', this.frags.length))}</span></div>`;
      const cv = this.filmEl.querySelector('canvas');
      requestAnimationFrame(() => { if (this.alive) this.drawFilm(cv); });
    },
    drawFilm(cv) {
      const film = this.d.film, frs = this.frags, R = rng(hash(film.id || 'film'));
      const dpr = (window.devicePixelRatio || 1) * (NZA.zoom || 1);
      const W = Math.max(10, Math.round(cv.clientWidth * dpr)), H = Math.max(10, Math.round(cv.clientHeight * dpr));
      cv.width = W; cv.height = H;
      const x = cv.getContext('2d');
      const motion = film.quality === 'motion';
      const ap = { w: W * 0.72, h: H }, lat = { x: W * 0.74, w: W * 0.26, h: H };
      const fov = this.R0 / MM * 2.2, sc = ap.w / fov, cx = ap.w / 2, cy = ap.h / 2;
      x.fillStyle = '#030404'; x.fillRect(0, 0, W, H);
      // soft tissue
      let gr = x.createRadialGradient(cx, cy, 0, cx, cy, ap.w * 0.8);
      gr.addColorStop(0, '#3b3f42'); gr.addColorStop(0.7, '#26292b'); gr.addColorStop(1, '#101213');
      x.fillStyle = gr; x.fillRect(0, 0, ap.w, ap.h);
      // anatomy by region
      const reg = String(this.inj.region || '').replace(/^[lr]_/, '');
      x.save();
      if (motion) x.filter = 'blur(2px)';
      if (/arm|leg/.test(reg)) {
        const bw = (/upper_leg/.test(reg) ? 28 : /lower_leg/.test(reg) ? 22 : /upper_arm/.test(reg) ? 22 : 15) * sc;
        const by = cy + (R() - 0.5) * 18 * sc + 14 * sc;
        gr = x.createLinearGradient(0, by - bw / 2, 0, by + bw / 2);
        gr.addColorStop(0, '#d9dcd8'); gr.addColorStop(0.18, '#8e9290'); gr.addColorStop(0.5, '#6b6f6e'); gr.addColorStop(0.82, '#8e9290'); gr.addColorStop(1, '#d9dcd8');
        x.fillStyle = gr; x.fillRect(0, by - bw / 2, ap.w, bw);
      } else if (reg === 'chest' || reg === 'back') {
        x.strokeStyle = 'rgba(205,210,206,.62)'; x.lineCap = 'round';
        for (let i = -3; i <= 3; i++) {
          x.lineWidth = 9 * sc;
          x.beginPath(); x.moveTo(-10, cy + i * 24 * sc - 22 * sc); x.quadraticCurveTo(cx, cy + i * 24 * sc + 10 * sc, ap.w + 10, cy + i * 24 * sc + 18 * sc); x.stroke();
        }
      } else if (reg === 'abdomen' || reg === 'pelvis') {
        x.fillStyle = 'rgba(8,9,10,.55)';
        for (let i = 0; i < 9; i++) { x.beginPath(); x.ellipse(R() * ap.w, R() * ap.h, (6 + R() * 12) * sc, (4 + R() * 7) * sc, R() * 3, 0, TAU); x.fill(); }
        if (reg === 'pelvis') { x.strokeStyle = 'rgba(200,204,200,.55)'; x.lineWidth = 12 * sc; x.beginPath(); x.arc(cx, ap.h + 30 * sc, ap.w * 0.6, Math.PI * 1.15, Math.PI * 1.85); x.stroke(); }
      } else {
        x.strokeStyle = 'rgba(214,218,214,.7)'; x.lineWidth = 7 * sc;
        x.beginPath(); x.arc(cx, cy + ap.h * 0.65, ap.h * 0.85, Math.PI * 1.2, Math.PI * 1.8); x.stroke();
      }
      x.restore();
      // metal: pure white with a halo
      const drawFrag = (fx, fy, f, s) => {
        x.save(); x.translate(fx, fy); x.rotate(f.rot);
        if (motion) x.filter = 'blur(2.5px)';
        x.shadowColor = 'rgba(255,255,255,.9)'; x.shadowBlur = 10 * (dpr / 2);
        x.fillStyle = '#ffffff';
        const L = f.size * s;
        if (f.shape === 'bullet') {
          x.beginPath(); x.ellipse(0, 0, L * 0.45, L * 0.3, 0, 0, TAU); x.fill();
          x.beginPath(); x.ellipse(L * 0.3, 0, L * 0.18, L * 0.42, 0, 0, TAU); x.fill();
        } else {
          const r2 = rng(hash(f.id));
          x.beginPath();
          for (let i = 0; i < 7; i++) { const a = i / 7 * TAU, rr = L * (0.25 + r2() * 0.3); x.lineTo(Math.cos(a) * rr * 1.3, Math.sin(a) * rr * 0.75); }
          x.closePath(); x.fill();
        }
        x.restore();
      };
      frs.forEach(f => { if (!f.out) drawFrag(cx + f.x * sc, cy + f.y * sc, f, sc); });
      // entry wound: a faint dark air track
      x.fillStyle = 'rgba(0,0,0,.45)'; x.beginPath(); x.arc(cx, cy, 3 * sc, 0, TAU); x.fill();
      // lateral strip: depth below the skin
      x.fillStyle = '#16191a'; x.fillRect(lat.x, 0, lat.w, lat.h);
      const top = 26 * (dpr / 2), maxD = Math.max(this.boneDepth + 8, 30), ds = (lat.h - top - 18 * (dpr / 2)) / maxD;
      gr = x.createLinearGradient(0, top, 0, lat.h);
      gr.addColorStop(0, '#3a3e40'); gr.addColorStop(1, '#202325');
      x.fillStyle = gr; x.fillRect(lat.x, top, lat.w, lat.h - top);
      x.fillStyle = 'rgba(205,210,206,.55)'; x.fillRect(lat.x, top + this.boneDepth * ds, lat.w, 10 * ds);
      x.strokeStyle = 'rgba(255,255,255,.35)'; x.lineWidth = 1; x.beginPath(); x.moveTo(lat.x, top); x.lineTo(lat.x + lat.w, top); x.stroke();
      frs.forEach((f, i) => { if (!f.out) drawFrag(lat.x + lat.w * (0.3 + 0.4 * ((i + 0.5) / frs.length)), top + f.depth * ds, f, ds * 0.9); });
      // labels
      const fs = Math.round(10 * (dpr / 1.5));
      x.font = `600 ${fs}px "JetBrains Mono", monospace`; x.fillStyle = 'rgba(255,255,255,.75)'; x.textBaseline = 'top';
      x.fillText('NAYZEEE RADIOLOGY', 8 * (dpr / 1.5), 8 * (dpr / 1.5));
      x.fillText(`${film.id || ''} AP`, 8 * (dpr / 1.5), 8 * (dpr / 1.5) + fs * 1.3);
      x.fillText('LAT', lat.x + 6 * (dpr / 1.5), 8 * (dpr / 1.5));
      x.font = `700 ${Math.round(fs * 1.8)}px "JetBrains Mono", monospace`; x.fillText('R', ap.w - fs * 2, 8 * (dpr / 1.5));
      x.font = `600 ${fs}px "JetBrains Mono", monospace`;
      frs.forEach((f, i) => { if (!f.out) { const yy = top + f.depth * ds; x.fillStyle = '#0fd4c4'; x.fillText(`${Math.round(f.depth)}`, lat.x + lat.w - fs * 2.2, yy - fs * 0.5 + i * 2); } });
      // 10 mm scale bar
      x.fillStyle = 'rgba(255,255,255,.8)'; x.fillRect(10 * (dpr / 1.5), H - 14 * (dpr / 1.5), 10 * sc, 2 * (dpr / 1.5));
      x.fillText('10 mm', 14 * (dpr / 1.5) + 10 * sc, H - 19 * (dpr / 1.5));
      // grain
      const img = x.getImageData(0, 0, W, H), px = img.data;
      for (let i = 0; i < px.length; i += 4) { const n = (Math.random() - 0.5) * 18; px[i] += n; px[i + 1] += n; px[i + 2] += n; }
      x.putImageData(img, 0, 0);
    },

    /* ═════════════ 2 · DISINFECT ═════════════ */
    startPrep() {
      const g = this.g, S = this.S, cfg = this.cfg;
      const found = this.frags.filter(f => f.found && !f.out);
      g.io.center = found.length ? this.fragCentroid(found) : this.entryUv.slice();
      const r = Math.min(cfg.prepRadius, this.R0 / MM - 4);
      g.io.radius = r;
      g.io.mask = S.layers.mask([g.io.center], r * MM);
      S.markers.set('prep', { uv: g.io.center, kind: 'dashed', size: r * 2 * MM, color: 0xffffff, pulse: false, opacity: 0.5 });
    },
    tickSwab(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, io = g.io, tool = this.tl.swab, hit = S.tools.hit;
      if (g.step !== 2) { if (g.lmb) this.cursorHint(T('swab_late', 'Prep is done'), ''); return; }
      if (io.redip > 0) {
        io.redip -= dt;
        this.cursorProgress(1 - clamp(io.redip / cfg.redipTime, 0, 1), T('cur_redip', 'Fresh swab…'));
        if (io.redip <= 0) { io.load = 1; tool.set({ load: 1 }); }
        return;
      }
      if (!g.lmb || !hit) { tool.set({ squash: 0 }); io.last = null; return; }
      if (!this.inWindow(hit.uv)) { io.last = null; this.cursorHint(T('cur_drape', 'On the drape — no effect'), 'amber'); return; }
      tool.set({ squash: 1 });
      const cur = hit.uv.slice();
      if (io.last) {
        const dmm = S.distanceUv(io.last, cur) / MM;
        if (dmm > 0.3) {
          const amt = 0.5 * (0.35 + 0.65 * io.load);
          S.layers.stroke('iodine', io.last, cur, cfg.swabRadius * MM, amt, { hardness: 0.3, grain: 0.3, grainScale: 90 });
          S.layers.stroke('wet', io.last, cur, cfg.swabRadius * MM, 0.3, { hardness: 0.2 });
          io.load = Math.max(0, io.load - dmm / cfg.swabReach);
          io.dist += dmm;
          tool.set({ load: io.load });
          const r = S.distanceUv(cur, io.center) / MM;
          io.rMax = Math.max(io.rMax, r);
          if (io.rMax > 14 && r < io.rMax * 0.35 && g.t - io.backT > 2) {
            io.back++; io.backT = g.t;
            this.flash('warn', T('swab_back_f', 'Back over the centre — that drags skin flora into the site. Work outward.'), 2600);
          }
          if (io.load <= 0) { io.redip = cfg.redipTime; io.dips++; }
          io.last = cur;
        }
      } else {
        S.layers.paint('iodine', cur, cfg.swabRadius * MM, 0.3, { hardness: 0.3 });
        io.last = cur;
      }
    },

    /* ═════════════ 3 · INCISE ═════════════ */
    startCut() {
      const g = this.g, S = this.S, c = g.cut, hit = S.tools.hit;
      if (!hit) return;
      if (g.step < 3) return;
      if (g.step > 5 || (g.xt.out.length && !this.remaining().length)) return this.flash('warn', T('cut_late', 'No more cutting — the fragments are out.'));
      if (g.xt.grip) return;
      if (!this.inWindow(hit.uv)) return this.flash('warn', T('off_window', 'Work inside the drape window.'));
      if (c.w) {
        const p = c.path, a = p[0], b = p[p.length - 1];
        const da = S.distanceUv(hit.uv, a) / MM, db = S.distanceUv(hit.uv, b) / MM;
        if (Math.min(da, db) > 3.5) { c.refused++; return this.flash('warn', T('cut_extend', 'To lengthen the incision, start at one of its ends.')); }
        if (c.path.length >= this.cfg.maxPoints - 2) return this.flash('warn', T('cut_max', 'That is as long as the incision can go.'));
        if (da < db) p.reverse();
        c.ext++;
      } else {
        c.path = [hit.uv.slice()];
      }
      c.drawing = true; c.speed = 0; c.strokeLen = 0;
      S.tools.press(true);
      if (c.blade < this.band()[0]) c.shallow++;
      if (this.hurt(18, this.cfg.flinchChance)) c.jolt = true;
      this.snd('noise', 120, { vol: 0.03, lp: 4000, hp: 1500 });
    },
    tickCut(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, c = g.cut, hit = S.tools.hit, tool = S.tools.active;
      if (tool) tool.pose.pressLift = c.drawing ? -Math.min(c.blade, 8) * MM * 0.3 : -0.0008;
      if (!c.drawing || !hit) return;
      let uv = hit.uv;
      if (c.jolt) {
        c.jolt = false;
        const st = S.uvToST(uv), a = Math.random() * TAU, r = (1.5 + Math.random() * 2) * MM;
        uv = S.stToUv(st[0] + Math.cos(a) * r, st[1] + Math.sin(a) * r);
        c.jag = Math.min(0.6, c.jag + 0.2);
      }
      const last = c.path[c.path.length - 1];
      const dmm = S.distanceUv(last, uv) / MM;
      c.speed = lerp(c.speed, dmm / Math.max(dt, 1e-3), 1 - Math.exp(-dt * 10));
      if (c.speed > cfg.cutFast) { c.fast += dt; c.jag = Math.min(0.6, c.jag + dt * 0.4); }
      if (dmm >= 1.1) {
        if (c.path.length >= cfg.maxPoints) { this.cursorHint(T('cut_max_cur', 'Lift the blade'), 'amber'); return; }
        if (!this.inWindow(uv)) { this.cursorHint(T('cur_drape', 'On the drape — no effect'), 'amber'); return; }
        c.path.push(uv.slice());
        c.dirty = true;
        c.strokeLen += dmm;
        S.layers.stroke('blood', last, uv, 0.45 * MM, 0.42, { hardness: 0.5 });
        if (tool) { const a = S.uvToST(last), b = S.uvToST(uv); tool.pose.yaw = Math.atan2(-(a[1] - b[1]), a[0] - b[0]) * 0.6 + tool.pose.yaw * 0.4; }
        const band = this.band(), extra = Math.max(0, c.blade - band[1]);
        this.addLoss(dmm * (0.25 + extra * 0.08));
        const L = (c.L || 0) + c.strokeLen;
        if (L > c.ideal * 1.3) this.addLoss(dmm * 0.6);
        if (Math.random() < dt * 2) this.snd('noise', 90, { vol: 0.02, lp: 5000, hp: 2000 });
      }
      if (c.dirty && g.t - c.lastBuild > 0.06) this.buildIncision();
      if (Math.random() < dt * 0.4 && this.hurt(5, cfg.flinchChance * 0.5)) c.jolt = true;
    },
    buildIncision() {
      const g = this.g, S = this.S, c = g.cut;
      c.dirty = false; c.lastBuild = g.t;
      if (c.path.length < 2) return;
      if (c.w) { S.fluids.bleed(c.w, 0); c.w.remove(); }
      c.w = S.wounds.add({ type: 'incision', points: c.path.map(p => p.slice()), gape: this.gapeNow() * MM, depth: this.depthVis() * MM, jagged: clamp(c.jag, 0, 0.6), rim: 0.15, seed: 23 });
      g.ex.applied = -1;
      if (!g.bl.rate) g.bl.rate = clamp((+this.inj.bleed || 0) * 0.35, 1.2, 12) + 1;
      this.setBleed();
    },
    endCut() {
      const g = this.g, S = this.S, c = g.cut, cfg = this.cfg;
      c.drawing = false;
      S.tools.press(false);
      if (c.dirty) this.buildIncision();
      if (!c.w) { c.path = []; return; }
      c.strokes++;
      c.L = c.w.length / MM;
      c.deepMax = Math.max(c.deepMax, c.blade);
      const band = this.band();
      if (c.blade > band[1] + 3 && !c.muscle) {
        c.muscle = true; g.bl.rate += 3;
        this.addLoss(14, 'muscle');
        this.flash('bad', T('cut_muscle', 'Too deep — you cut into the muscle. It bleeds.'), 3000);
        this.snd('fail');
        this.refreshTools();
        return;
      }
      if (c.L < cfg.minCut) return this.flash('warn', T('cut_short', 'Only %s mm — keep cutting over the fragment.', Math.round(c.L)));
      const miss = this.remaining().filter(f => !this.underCut(f));
      if (miss.length) {
        const any = miss.some(f => f.found);
        return this.flash('warn', any ? T('cut_miss', 'The fragment is not under your cut — extend it toward the mark.') : T('cut_blind', 'Nothing under the cut yet — extend it, or find the fragment with the probe {1}.'), 3200);
      }
      c.covered = true;
      if (c.L > c.ideal * 1.45) this.flash('warn', T('cut_long', 'Longer than it needs to be (%s mm) — more blood loss.', Math.round(c.L)), 2600);
      if (g.step === 3) this.completeStep(3, T('s3_done', 'Incision %s mm — through skin and fat.', Math.round(c.L)));
      this.markFrags();
    },

    /* ═════════════ 4 · EXPOSE (retractor, suction, gauze) ═════════════ */
    tickSpread(dt) {
      const g = this.g, cfg = this.cfg, c = g.cut, ex = g.ex;
      if (!c.w) return;
      if (ex.space && g.step >= 4 && g.step <= 6 && !g.xt.grip) {
        ex.spread = Math.min(1.3, ex.spread + dt / cfg.spreadTime);
        if (ex.spread > cfg.tearAt) {
          ex.overT += dt;
          this.cursorHint(T('cur_tear', 'Too wide — tearing'), 'red');
          if (ex.overT > 0.35) {
            ex.tears++; ex.overT = 0; ex.space = false; ex.spread = 1.0;
            g.bl.rate += 1.5; g.bl.boost += 3;
            this.addLoss(10, 'tear');
            this.hurt(20, cfg.flinchChance);
            this.flash('bad', T('spread_tear', 'Spread too far — the tissue tore.'), 2800);
            this.snd('fail');
          }
        } else this.cursorProgress(clamp(ex.spread / cfg.tearAt, 0, 1), '');
      }
      const want = Math.round(this.gapeNow() * 20) / 20;
      if (want !== ex.applied) { ex.applied = want; c.w.set({ gape: want * MM, depth: this.depthVis() * MM }); }
    },
    tickSuction(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, hit = S.tools.hit, tool = this.tl.suction;
      if (!g.lmb || !hit) { tool.set({ flow: 0 }); return; }
      const r = cfg.suctionRadius * MM;
      const before = S.layers.total('blood', hit.uv, r * 1.4) + 0.5 * S.layers.total('clot', hit.uv, r);
      S.layers.erase('blood', hit.uv, r, 4.5 * dt, { hardness: 0.3 });
      S.layers.erase('clot', hit.uv, r * 0.8, 0.9 * dt, { hardness: 0.3 });
      S.layers.erase('wet', hit.uv, r, 1.2 * dt, { hardness: 0.2 });
      const after = S.layers.total('blood', hit.uv, r * 1.4) + 0.5 * S.layers.total('clot', hit.uv, r);
      const got = Math.max(0, before - after);
      g.su.ml += got * 0.004;
      tool.set({ flow: clamp(0.25 + got * 0.02, 0.25, 1) });
      g.su.flowT -= dt;
      if (g.su.flowT <= 0) { g.su.flowT = 0.28; this.snd('noise', 260, { vol: got > 5 ? 0.05 : 0.025, lp: got > 5 ? 900 : 2400, hp: 200 }); }
    },
    tickGauze(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, gz = g.gz, tool = S.tools.active, hit = S.tools.hit;
      if (!g.lmb || !hit) { if (tool) tool.set({ squash: 0 }); return; }
      if (!gz.swab) {
        if (gz.used >= gz.have) { this.cursorHint(T('gauze_out', 'No gauze left'), 'red'); return; }
        gz.used++;
        gz.swab = { load: 0, stains: 0 };
        if (tool) tool.set({ fresh: true });
        this.refreshTools();
      }
      if (tool) tool.set({ squash: 1 });
      S.tools.press(true);
      const uv = hit.uv, r = cfg.gauzeRadius * MM;
      const before = S.layers.total('blood', uv, r) + 0.6 * S.layers.total('clot', uv, r);
      S.layers.erase('blood', uv, r, 3.0 * dt, { hardness: 0.25 });
      S.layers.erase('clot', uv, r * 0.9, 0.4 * dt, { hardness: 0.25 });
      S.layers.erase('wet', uv, r, 1.4 * dt, { hardness: 0.2 });
      const after = S.layers.total('blood', uv, r) + 0.6 * S.layers.total('clot', uv, r);
      const got = Math.max(0, before - after);
      gz.swab.load += got * 0.03; gz.absorbed += got * 0.03;
      // pressure on the bleeding point (control bleeding)
      if (g.cut.w && g.step >= 5 && g.step <= 6) {
        const dmm = S.distanceUv(uv, this.bleederUv()) / MM;
        const eff = dmm <= cfg.pressRadius ? 1 : 0.2;
        g.bl.rate = Math.max(0.2, g.bl.rate * Math.exp(-cfg.pressRate * eff * dt));
        g.bl.boost *= Math.exp(-cfg.pressRate * 2 * eff * dt);
        g.hm.press += dt * eff;
        if (g.step === 6) this.cursorProgress(clamp(1 - (this.bleedNow() - cfg.bleedDone) / Math.max(0.1, g.hm.start - cfg.bleedDone), 0, 1), eff < 1 ? T('cur_off_bleeder', 'Not on the bleeding point') : '');
      }
      gz.stainT -= dt;
      if (got > 1 && gz.stainT <= 0 && gz.swab.stains < 14 && tool) {
        gz.stainT = 0.22; gz.swab.stains++;
        const k = clamp(gz.swab.load / cfg.gauzeCapacity, 0, 1);
        tool.set({ stain: { x: 0.5 + (Math.random() - 0.5) * (0.25 + k * 0.4), y: 0.5 + (Math.random() - 0.5) * (0.25 + k * 0.4), r: 0.08 + k * 0.22, a: 0.55 + k * 0.4 } });
      }
      if (g.step !== 6) this.cursorProgress(clamp(gz.swab.load / cfg.gauzeCapacity, 0, 1), '', true);
      if (gz.swab.load >= cfg.gauzeCapacity) {
        gz.swab = null;
        this.flash('warn', gz.used < gz.have ? T('gauze_soaked', 'That swab is soaked — the next press opens a fresh one.') : T('gauze_last', 'That was your last swab.'));
        this.refreshTools();
      }
    },

    /* ═════════════ 5 · EXTRACT ═════════════ */
    grab() {
      const g = this.g, S = this.S, cfg = this.cfg, hit = S.tools.hit, x = g.xt, tool = this.tl.forceps;
      if (!hit || g.step !== 5) return;
      if (g.ex.spread < 0.55) return this.flash('warn', T('need_spread', 'Spread the incision first {Space}.'));
      let best = null, bd = Infinity;
      for (const f of this.remaining()) { const d = S.distanceUv(hit.uv, f.uv) / MM; if (d < bd) { bd = d; best = f; } }
      tool.set({ open: 0.1 });
      this.snd('tone', 1600, 30, { vol: 0.04, type: 'square' });
      if (!best || bd > best.size / 2 + cfg.grabTol) {
        x.misses++;
        this.addLoss(1.5, 'miss');
        S.layers.paint('blood', hit.uv, 1.2 * MM, 0.4, { hardness: 0.4 });
        this.hurt(12, cfg.flinchChance * 0.6);
        setTimeout(() => { if (this.tl && g.tool === 'forceps' && !x.grip) this.tl.forceps.set({ open: 0.75 }); }, 260);
        return this.flash('bad', T('grip_miss', 'The jaws closed on tissue — aim at the metal.'), 2200);
      }
      if (S.layers.average('blood', best.uv, 3 * MM) > 0.55) {
        setTimeout(() => { if (this.tl && !x.grip) this.tl.forceps.set({ open: 0.75 }); }, 260);
        return this.flash('warn', T('grip_blind', 'Blood is hiding it — suction {4} first.'));
      }
      x.grip = best;
      best.exposed = true;
      x.strength = clamp(1 - Math.max(0, bd - best.size * 0.25) / (best.size / 2 + cfg.grabTol), 0.45, 1);
      x.grip0 = x.strength;
      x.lastY = this.my; x.speed = 0;
      S.tools.follow = false;
      S.tools.press(true);
      this.hurt(8, cfg.flinchChance * 0.4);
      this.flash('ok', best.lodge > 0 ? T('grip_lodged', 'Gripped — it is lodged. Rock it free with {A} / {D}.') : T('grip_ok', 'Gripped (%s%) — now draw the mouse back slowly.', pct(x.strength)), 2200);
    },
    releaseGrip(byUser) {
      const g = this.g, x = g.xt, S = this.S;
      if (!x.grip) return;
      x.grip = null; x.speed = 0;
      S.tools.follow = true;
      S.tools.press(false);
      Object.assign(this.tl.forceps.pose, { lift: this.tl.forceps.base.lift });
      this.tl.forceps.set({ open: 0.75 });
      if (byUser) this.flash('warn', T('grip_let', 'Let go — grip it again to carry on.'), 1800);
    },
    rock(dir) {
      const g = this.g, x = g && g.xt;
      if (!x || !x.grip || x.grip.lodge <= 0) return;
      if (dir === x.rockSide) return this.flash('warn', T('rock_alt', 'Alternate — {A} then {D}.'), 1400);
      x.rockSide = dir;
      x.grip.lodge = Math.max(0, x.grip.lodge - 1 / this.cfg.rocks);
      this.tl.forceps.pose.roll = dir * 0.35;
      setTimeout(() => { if (this.tl) this.tl.forceps.pose.roll = 0; }, 160);
      this.hurt(6, this.cfg.flinchChance * 0.3);
      this.snd('tone', 700 + Math.random() * 200, 40, { vol: 0.03, type: 'triangle' });
      if (x.grip.lodge <= 0) this.flash('ok', T('rock_free', 'It moved — now draw it out slowly.'), 2000);
    },
    tickForceps(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, x = g.xt, tool = this.tl.forceps;
      if (!x.grip) {
        if (g.step === 5 && !this.remaining().length) return;
        const hit = S.tools.hit;
        if (hit && g.step === 5) {
          const f = this.remaining().find(q => S.distanceUv(hit.uv, q.uv) / MM <= q.size / 2 + cfg.grabTol);
          if (f) this.cursorHint(T('cur_grip', 'Grip'), 'teal');
        }
        return;
      }
      const f = x.grip;
      const dy = (this.my - x.lastY) / window.innerHeight;
      x.lastY = this.my;
      const v = Math.abs(dy) / Math.max(dt, 1e-3);
      x.speed = lerp(x.speed, v, 1 - Math.exp(-dt / 0.12));
      if (f.lodge > 0) {
        f.prog = Math.min(f.prog + Math.max(0, dy) / cfg.pullDist * 0.25, 0.12);
        if (dy > 0.002) this.cursorHint(T('cur_lodged', 'Lodged — rock {A} {D}').replace(/[{}]/g, ''), 'amber');
      } else {
        if (dy > 0) f.prog += dy / cfg.pullDist;
        else { f.prog = Math.max(0, f.prog + dy / cfg.pullDist * 0.5); if (dy < -0.004) x.pushes++; }
      }
      if (x.speed > cfg.pullSafe) x.strength -= (x.speed - cfg.pullSafe) * cfg.gripLoss * dt;
      else x.strength = Math.min(x.grip0, x.strength + 0.15 * dt);
      if (x.speed > cfg.pullSlip || x.strength <= 0) { this.slip(); return; }
      tool.pose.lift = tool.base.lift + f.prog * 0.035;
      if (x.speed > cfg.pullSafe) this.cursorHint(T('cur_slow', 'Slower!'), x.speed > cfg.pullSlip * 0.8 ? 'red' : 'amber');
      if (f.prog >= 1) this.extracted(f);
    },
    slip() {
      const g = this.g, x = g.xt, f = x.grip;
      x.slips++;
      f.prog *= 0.4;
      g.bl.rate += 1; g.bl.boost += 4;
      this.addLoss(12, 'slip');
      this.S.layers.splat('blood', f.uv, 3.5 * MM, 0.6, { seed: x.slips * 7 });
      this.S.controls.shake(0.4, 260);
      this.hurt(22, this.cfg.flinchChance);
      this.releaseGrip(false);
      this.flash('bad', T('grip_slip', 'Too fast — it slipped and tore the tissue.'), 2800);
      this.snd('fail');
    },
    extracted(f) {
      const g = this.g, S = this.S, x = g.xt;
      f.out = true; f.prog = 1;
      x.out.push(f.id);
      // into the kidney dish
      const m = f.mesh;
      f.flyT = 0; f.flyFrom = m.position.clone();
      const side = S.surfaceAt(S.stToUv(this.R0 * 1.6, -this.R0 * 0.4)).point;
      f.flyTo = side.clone().add(new (T3().Vector3)(0, 0.05, 0));
      f.flyUp = new (T3().Vector3)(0, 1, 0);
      this.releaseGrip(false);
      g.bl.rate += 1.5;
      S.layers.splat('blood', f.uv, 2.4 * MM, 0.45, { seed: x.out.length * 13 });
      this.markFrags();
      this.refreshTools();
      const left = this.remaining().length;
      if (!left) this.completeStep(5, this.frags.length > 1 ? T('s5_done_n', 'All %s fragments are out.', this.frags.length) : T('s5_done', 'Projectile out — in the dish.'));
      else this.flash('ok', T('xt_one', 'Fragment %s out — %s to go.', f.n, left), 2400);
      this.snd('success');
    },
    leaveRest() {
      const g = this.g;
      if (!g || g.step !== 5 || this.finished) return;
      if (!g.xt.out.length) return this.flash('warn', T('leave_none', 'Get at least one fragment out first.'));
      const now = performance.now();
      if (this.leaveArm && now - this.leaveArm < 2800) {
        this.leaveArm = 0;
        g.xt.left = true;
        this.releaseGrip(false);
        this.completeStep(5, T('leave_done', 'Leaving %s fragment(s) in — control the bleeding.', this.remaining().length));
        return;
      }
      this.leaveArm = now;
      this.flash('warn', T('leave_confirm', 'Leave %s fragment(s) in the wound? Press {L} again.', this.remaining().length), 2800);
    },

    /* ═════════════ 7 · SUTURE ═════════════ */
    startSuture() {
      const g = this.g, S = this.S, w = g.cut.w, cfg = this.cfg;
      if (!w) return;
      g.ex.spread = 0; g.ex.space = false;
      w.set({ gape: 2.4 * MM, depth: Math.min(this.depthVis(), 5) * MM, open: 1 });
      g.ex.applied = 2.4;
      const L = w.length / MM;
      this.Lmm = L;
      S.layers.erase('blood', w.at(0.5).uv, (L / 2 + 3) * MM, 0.5, { hardness: 0.2 });
      g.sut.N = clamp(Math.round(L / cfg.mmPerStitch), cfg.minStitches, cfg.maxStitches);
      const pa = S.project(w.edge(0.5, 1, 0.004)), pb = S.project(w.edge(0.5, -1, 0.004));
      this.near = pa.y > pb.y ? 1 : -1;
      this.frameOn(w.at(0.5).uv, clamp(L * 2.1 * MM, 0.05, 0.12));
      this.sutureMarkers();
      this.renderDots();
    },
    closedFrac() {
      const g = this.g;
      if (!g || !g.sut.N) return 0;
      return this.coveredSlots().filter(Boolean).length / g.sut.N;
    },
    coveredSlots() {
      const g = this.g, N = g.sut.N, out = new Array(N).fill(false);
      for (const s of g.sut.list) {
        const i = clamp(Math.floor(s.tN * N), 0, N - 1);
        if (Math.abs(s.tN - (i + 0.5) / N) * this.Lmm <= (this.Lmm / N) * 0.62) out[i] = true;
      }
      return out;
    },
    nextSlot() { return this.coveredSlots().indexOf(false); },
    sutureMarkers() {
      const g = this.g, S = this.S, cfg = this.cfg, w = g.cut.w;
      if (!S || g.step !== 7 || !w) return;
      const i = this.nextSlot();
      if (i < 0) { S.markers.remove('in'); S.markers.remove('inR'); S.markers.remove('out'); return; }
      const tN = (i + 0.5) / g.sut.N;
      const a = w.edge(tN, this.near, cfg.bite * MM), b = w.edge(tN, -this.near, cfg.bite * MM);
      S.markers.set('inR', { uv: a, kind: 'ring', size: 0.0034, color: 0x0fd4c4, pulse: true });
      S.markers.set('in', { uv: a, kind: 'pin', size: 0.0052, color: 0x0fd4c4, lift: 0.008 });
      S.markers.set('out', { uv: b, kind: 'dashed', size: 0.0036, color: 0xffffff, pulse: false, opacity: 0.7 });
    },
    edgeDist(uv) {
      const w = this.g.cut.w, loc = w.locate(uv);
      return { loc, mm: (loc.d - w.halfGape(loc.tN)) / MM };
    },
    startStitch() {
      const g = this.g, S = this.S, cfg = this.cfg, hit = S.tools.hit;
      if (g.step !== 7 || !g.cut.w) return this.flash('warn', T('sut_wrong_step', 'Not yet — finish the current step first.'));
      if (!hit) return;
      const { loc, mm } = this.edgeDist(hit.uv);
      if (loc.tN < 0.03 || loc.tN > 0.97) return this.flash('bad', T('sut_ends', 'Stay along the cut, not past its ends.'));
      if (loc.side !== this.near) return this.flash('bad', T('sut_near', 'Start on the **near** edge — the side closest to you.'));
      if (mm < cfg.biteMin) return this.flash('bad', T('sut_close', 'Too close to the edge — that bite would tear out.'));
      if (mm > cfg.biteMax) return this.flash('bad', T('sut_far', 'Too far from the cut — start at the marker.'));
      for (const s of g.sut.list) if (Math.abs(s.tN - loc.tN) * this.Lmm < 2.6) return this.flash('warn', T('sut_taken', 'There is already a stitch here.'));
      if (g.sut.list.length >= g.sut.N + cfg.extraStitches) return this.flash('warn', T('sut_max', 'That is enough thread for this cut.'));
      g.sut.drag = { a: hit.uv.slice(), aTN: loc.tN, aMm: mm, t0: g.t, jit: [0, 0], flinch: false };
      S.tools.press(true);
      const tool = S.tools.active; if (tool) tool.set({ open: 0 });
      this.snd('tone', 520, 30, { vol: 0.03, type: 'triangle' });
      if (this.hurt(14, cfg.flinchChance * 0.6)) this.jolt();
    },
    jolt() {
      const d = this.g.sut.drag;
      if (!d) return;
      const a = Math.random() * TAU, r = (1.2 + Math.random() * 1.6) * MM;
      d.jit[0] += Math.cos(a) * r; d.jit[1] += Math.sin(a) * r;
      d.flinch = true;
    },
    tickStitch(dt) {
      const g = this.g, S = this.S, d = g.sut.drag;
      if (!d) return;
      const hit = S.tools.hit;
      S.stitches.preview(d.a, hit ? hit.point : null);
      if (hit) {
        const { loc, mm } = this.edgeDist(hit.uv);
        const across = loc.side !== this.near;
        this.cursorHint(across ? (mm >= this.cfg.biteMin ? T('cur_release', 'Release to tie') : T('cur_further', 'A little further')) : T('cur_pull', 'Pull across the cut'), across && mm >= this.cfg.biteMin ? 'teal' : '');
      }
      if (Math.random() < dt * 0.3 && this.hurt(5, this.cfg.flinchChance * 0.5)) this.jolt();
    },
    cancelDrag() {
      const g = this.g;
      g.sut.drag = null;
      this.S.stitches.preview(null);
      this.S.tools.press(false);
    },
    endStitch() {
      const g = this.g, S = this.S, cfg = this.cfg, d = g.sut.drag, w = g.cut.w;
      g.sut.drag = null;
      S.stitches.preview(null);
      S.tools.press(false);
      const hit = S.tools.hit;
      if (!hit || !d) return;
      const st = S.uvToST(hit.uv);
      const bUv = S.stToUv(st[0] + d.jit[0], st[1] + d.jit[1]);
      const { loc, mm } = this.edgeDist(bUv);
      const dur = g.t - d.t0;
      const miss = msg => { g.sut.misses++; this.hurt(6, 0); this.flash('bad', msg, 2800); this.snd('fail'); this.renderDots(); };
      if (loc.side === this.near || mm < cfg.biteMin * 0.6) return miss(d.flinch ? T('sut_miss_flinch', 'The patient flinched and the needle came out on the same side.') : T('sut_miss_side', 'The needle came out on the same side — pull across to the far edge.'));
      if (mm > cfg.biteMax + 2) return miss(T('sut_miss_far', 'Too far on the far side — that would pucker the skin.'));
      if (loc.tN < 0.01 || loc.tN > 0.99) return miss(T('sut_ends', 'Stay along the cut, not past its ends.'));
      const tMid = (d.aTN + loc.tN) / 2;
      const at = w.at(tMid);
      const sa = S.uvToST(d.a), sb = S.uvToST(bUv);
      const vx = sb[0] - sa[0], vy = sb[1] - sa[1], vl = Math.hypot(vx, vy) || 1;
      const perp = Math.acos(clamp(Math.abs((vx * at.nrm[0] + vy * at.nrm[1]) / vl), 0, 1)) * 180 / Math.PI;
      const ideal = cfg.bite;
      const biteQ = clamp(100 - 11 * Math.abs(d.aMm - ideal) - 11 * Math.abs(mm - ideal) - 8 * Math.abs(d.aMm - mm), 0, 100);
      const perpQ = clamp(100 - Math.max(0, perp - 6) * 2.6, 0, 100);
      const slot = clamp(Math.floor(tMid * g.sut.N), 0, g.sut.N - 1);
      const spaceMm = Math.abs(tMid - (slot + 0.5) / g.sut.N) * this.Lmm;
      const spaceQ = clamp(100 - Math.max(0, spaceMm - 0.8) * 14, 0, 100);
      const fast = dur < cfg.minDrag;
      const q = clamp(0.4 * biteQ + 0.3 * perpQ + 0.3 * spaceQ - (fast ? 15 : 0) - (d.flinch ? 8 : 0), 0, 100);
      S.stitches.add({ a: d.a, b: bUv, knot: 'b', seed: g.sut.list.length * 31 + 7 });
      w.close(tMid, 1, 0.5 / g.sut.N);
      g.sut.list.push({ tN: tMid, q, bite: [d.aMm, mm], perp, space: spaceMm, fast, flinch: d.flinch });
      this.hurt(6, 0);
      this.setBleed();
      S.layers.paint('blood', at.uv, [(this.Lmm / g.sut.N) * 0.45 * MM, (w.halfGape(tMid) + 0.0009)], 0.25, { hardness: 0.35, grain: 0.3, grainScale: 160, angle: Math.atan2(at.dir[1], at.dir[0]) });
      let fb;
      if (fast) fb = ['warn', T('fb_fast', 'Too fast — follow the curve of the needle.')];
      else if (biteQ < 60) fb = ['warn', T('fb_bite', 'Uneven bite — %s mm and %s mm. Aim for %s on both sides.', d.aMm.toFixed(1), mm.toFixed(1), ideal)];
      else if (perpQ < 60) fb = ['warn', T('fb_angle', 'Crooked stitch (%s°) — pull straight across the cut.', Math.round(perp))];
      else if (spaceQ < 60) fb = ['warn', T('fb_space', 'Off the marker by %s mm — keep the spacing even.', spaceMm.toFixed(1))];
      else fb = ['ok', T('fb_good', 'Good stitch — %s mm bites, %s° off square.', ((d.aMm + mm) / 2).toFixed(1), Math.round(perp))];
      this.flash(fb[0], fb[1], 2200);
      g.sut.last = fb;
      this.snd('click', q >= 70 ? 760 : 420);
      this.renderDots();
      if (this.coveredSlots().every(Boolean)) {
        S.markers.remove('in'); S.markers.remove('inR'); S.markers.remove('out');
        this.completeStep(7, T('s7_done', 'The incision is closed.'));
      } else if (g.sut.list.length >= g.sut.N + cfg.extraStitches) {
        this.completeStep(7, T('s7_done_gaps', 'Closed — with gaps between the stitches.'));
      } else {
        if (g.sut.list.length >= g.sut.N) this.flash('warn', T('sut_gap', 'There is still a gap — add a stitch at the marker.'), 2600);
        this.sutureMarkers();
      }
    },
    renderDots() {
      const g = this.g;
      if (!g || !this.dots || !g.sut.N) return;
      const N = g.sut.N, cov = this.coveredSlots(), next = this.nextSlot();
      const qBySlot = new Array(N).fill(null);
      for (const s of g.sut.list) { const i = clamp(Math.floor(s.tN * N), 0, N - 1); qBySlot[i] = qBySlot[i] === null ? s.q : Math.max(qBySlot[i], s.q); }
      this.dots.innerHTML = qBySlot.map((q, i) => `<i class="${cov[i] ? (q >= 75 ? 'ok' : q >= 50 ? 'mid' : 'bad') : i === next && g.step === 7 ? 'cur' : ''}"></i>`).join('');
    },

    /* ═════════════ 8 · DRESSING ═════════════ */
    coverPts() {
      const g = this.g, pts = g.cut.w ? g.cut.w.points() : [];
      return pts.concat([this.entryUv]);
    },
    startDressing() {
      const g = this.g, S = this.S;
      if (g.dr.D) return;
      if (g.ex.spread > 0 && g.cut.w) { g.ex.spread = 0; g.cut.w.set({ gape: 2.4 * MM, depth: 5 * MM }); }
      const pts = this.coverPts().map(p => S.uvToST(p));
      const w = g.cut.w, mid = w ? w.at(0.5) : { s: 0, t: 0, dir: [1, 0], nrm: [0, 1] };
      const dir = mid.dir, nrm = [-dir[1], dir[0]];
      let u0 = Infinity, u1 = -Infinity, v0 = Infinity, v1 = -Infinity;
      pts.forEach(p => { const dx = p[0] - mid.s, dy = p[1] - mid.t, u = dx * dir[0] + dy * dir[1], v = dx * nrm[0] + dy * nrm[1]; u0 = Math.min(u0, u); u1 = Math.max(u1, u); v0 = Math.min(v0, v); v1 = Math.max(v1, v); });
      const pw = clamp((u1 - u0) / MM + 12, 26, 80), ph = clamp((v1 - v0) / MM + 12, 18, 60);
      const dw = pw + 16, dh = ph + 16;
      const cu = (u0 + u1) / 2, cv = (v0 + v1) / 2;
      const cs = mid.s + dir[0] * cu + nrm[0] * cv, ct = mid.t + dir[1] * cu + nrm[1] * cv;
      g.dr.target = [cs, ct]; g.dr.nrm = nrm; g.dr.dh = dh;
      const viewW = clamp((Math.max(dw, dh) + 50) * MM, 0.08, this.R0 * 3);
      S.controls.frame(S.stToUv(cs, ct), viewW, { instant: false, pitch: 1.24 });
      const near = this.near || 1, off = (dh / 2 + 15) * MM, far = -near;
      const uv = S.stToUv(cs + nrm[0] * off * far, ct + nrm[1] * off * far);
      const ang = Math.atan2(-dir[1], dir[0]) + 0.1;
      g.dr.D = S.dressing.create({ size: [dw * MM, dh * MM], pad: [pw * MM, ph * MM], uv, angle: ang });
      g.dr.restUv = uv;
    },
    dressDown() {
      const g = this.g, S = this.S, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      const pick = D.pick(hit);
      if (pick === 'edge' && D.stuck < 0.25 && D.state !== 'carried') {
        if (D.grab(hit)) { this.stage.classList.add('grabbing'); this.snd('tone', 300, 40, { vol: 0.03, type: 'triangle' }); return; }
      }
      if (D.state === 'placed' || D.state === 'falling') { g.dr.rub = true; return; }
      if (pick === 'body') this.flash('warn', T('dress_edge', 'Pick it up by its **edge**.'));
      else if (D.stuck >= 0.25 && pick === 'edge') this.flash('warn', T('dress_stuck', 'It is already sticking — rub it down.'));
    },
    dressUp() {
      const g = this.g, D = g.dr.D;
      g.dr.rub = false;
      if (!D) return;
      if (D.state === 'carried') { D.release(); g.dr.settledT = 0; this.stage.classList.remove('grabbing'); }
    },
    tickDressing(dt) {
      const g = this.g, S = this.S, cfg = this.cfg, D = g.dr.D;
      if (!D) return;
      const hit = S.raycast();
      if (D.state === 'carried') { if (hit) D.move(hit); return; }
      if (!g.lmb) {
        const pick = hit ? D.pick(hit) : null;
        this.stage.classList.toggle('grab', pick === 'edge' && D.stuck < 0.25);
        if (pick === 'edge' && D.stuck < 0.25 && D.state === 'rest') this.cursorHint(T('cur_grab', 'Grab the edge'), 'teal');
      }
      if (D.state === 'placed' || D.state === 'falling') {
        g.dr.settledT += dt;
        if (g.dr.settledT > 0.4) {
          g.dr.cover = D.covers(this.coverPts());
          D.seep(clamp(0.15 + this.bleedNow() / 8, 0, 0.7) * clamp(g.dr.cover, 0.3, 1), g.cut.w ? g.cut.w.at(0.5).uv : this.entryUv);
        }
      }
      if (g.dr.rub && g.lmb && hit && (D.state === 'placed' || D.state === 'falling')) {
        D.rub(hit, dt);
        this.cursorProgress(D.stuck, '');
      }
      if (D.state === 'placed' && g.dr.settledT > 0.6 && g.dr.cover < cfg.coverMin && D.stuck < 0.25) {
        g.dr.warnT -= dt;
        if (g.dr.warnT <= 0) { g.dr.warnT = 5; this.flash('warn', T('dress_cover', 'The pad covers only %s% of the wound — lift it by an edge and try again.', pct(g.dr.cover)), 3600); }
      }
      if (!g.done[8] && D.stuck >= cfg.stuckDone && g.dr.settledT > 0.4) {
        g.dr.cover = D.covers(this.coverPts());
        this.completeStep(8, T('s8_done', 'Dressing on — %s% of the wound covered.', pct(g.dr.cover)));
      }
    },

    /* ═════════════ sound (only after real input) ═════════════ */
    snd(name, ...args) {
      if (!this.heard || !NZA.audio || typeof NZA.audio[name] !== 'function') return;
      try { NZA.audio[name](...args); } catch (e) { /* audio unavailable */ }
    },

    /* ═════════════ cursor ring ═════════════ */
    cursorProgress(p, text, red) { this.curP = { p, text, red, t: performance.now() }; },
    cursorHint(text, tone) { this.curH = { text, tone, t: performance.now() }; },
    updateCursor() {
      const now = performance.now();
      const cp = this.curP && now - this.curP.t < 160 ? this.curP : null;
      const ch = this.curH && now - this.curH.t < 160 ? this.curH : null;
      const on = !!(cp || ch);
      this.cur.classList.toggle('on', on);
      if (!on) return;
      this.cur.style.transform = `translate(${this.mx}px,${this.my}px)`;
      const p = cp ? clamp(cp.p, 0, 1) : 0;
      this.curFg.setAttribute('stroke-dasharray', `${(p * 119.4).toFixed(1)} 120`);
      this.cur.classList.toggle('red', !!(cp && cp.red && p > 0.85));
      this.cur.querySelector('svg').style.display = cp ? '' : 'none';
      const tx = (ch && ch.text) || (cp && cp.text) || '';
      if (this.curTx.textContent !== tx) this.curTx.textContent = tx;
      this.curTx.className = `tx ${(ch && ch.tone) || ''}`;
    },

    /* ═════════════ finish ═════════════ */
    computeResult() {
      const g = this.g, cfg = this.cfg, W = cfg.weights, N = this.frags.length;
      const film = this.d.film;
      const found = this.frags.filter(f => f.found).length;
      const method = g.film.used ? 'xray' : this.frags.some(f => f.how === 'probe') ? 'probe' : this.frags.some(f => f.how === 'palpate') ? 'palpate' : 'none';
      const locQ = g.skipped[1] ? 0 : method === 'xray' ? (film && film.quality === 'motion' ? 85 : 100) : clamp(100 * found / N - g.pr.falses * 15, 0, 100);
      const tech = clamp(1 - g.io.back * 0.15, 0, 1);
      const disQ = g.skipped[2] ? 0 : clamp(g.io.cov * 70 + tech * 30, 0, 100);
      const c = g.cut, band = this.band(), L = c.L || 0;
      const lenQ = clamp(100 - 4 * Math.max(0, c.ideal * 0.85 - L) - 3 * Math.max(0, L - c.ideal * 1.25), 0, 100);
      const depQ = c.deepMax > band[1] ? clamp(100 - (c.deepMax - band[1]) * 16, 0, 100) : c.blade < band[0] ? clamp(100 - (band[0] - c.blade) * 14, 0, 100) : 100;
      let straight = 100;
      if (c.w && c.path.length > 2) {
        const a = S2(this.S, c.path[0]), b = S2(this.S, c.path[c.path.length - 1]), ab = [b[0] - a[0], b[1] - a[1]], l = Math.hypot(ab[0], ab[1]) || 1;
        let dev = 0;
        c.path.forEach(p => { const q = S2(this.S, p); dev = Math.max(dev, Math.abs(((q[0] - a[0]) * ab[1] - (q[1] - a[1]) * ab[0]) / l)); });
        straight = clamp(100 - Math.max(0, dev / MM - 1.5) * 12, 0, 100);
      }
      const incQ = c.w ? clamp(lenQ * 0.45 + depQ * 0.3 + straight * 0.25 - c.ext * 5 - c.fast * 6 - (c.covered ? 0 : 40), 0, 100) : 0;
      const expQ = g.done[4] || g.xt.out.length ? clamp(100 - g.ex.tears * 22, 0, 100) : 0;
      const out = g.xt.out.length;
      const extQ = clamp(100 * out / N - g.xt.slips * 14 - g.xt.misses * 4, 0, 100);
      const bEnd = this.bleedNow();
      const hemQ = g.skipped[6] ? clamp(55 - bEnd * 6, 0, 55) : g.done[6] ? clamp(100 - Math.max(0, g.hm.press - 25) * 1.2, 60, 100) : 0;
      const list = g.sut.list.slice().sort((a, b) => a.tN - b.tN), SN = g.sut.N;
      const avgQ = list.length ? list.reduce((s, x) => s + x.q, 0) / list.length : 0;
      let evenQ = 0;
      if (list.length && SN) {
        const ideal = this.Lmm / SN, gaps = [];
        for (let i = 1; i < list.length; i++) gaps.push((list[i].tN - list[i - 1].tN) * this.Lmm);
        const dev = gaps.reduce((s, v) => s + Math.abs(v - ideal), 0) / Math.max(1, gaps.length);
        evenQ = clamp(100 - dev * 10, 0, 100);
      }
      const closed = this.closedFrac();
      const sutQ = g.skipped[7] ? 0 : clamp((avgQ * 0.65 + evenQ * 0.35) * closed - g.sut.misses * 4, 0, 100);
      const D = g.dr.D, stuck = D ? D.stuck : 0, cover = g.dr.cover || 0;
      const dresQ = g.skipped[8] ? 0 : clamp(cover * 70 + stuck * 30, 0, 100);
      const parts = { locate: locQ, disinfect: disQ, incise: incQ, expose: expQ, extract: extQ, haemostasis: hemQ, suture: sutQ, dressing: dresQ };
      let tw = 0, sum = 0;
      Object.keys(parts).forEach(k => { tw += W[k] || 0; sum += parts[k] * (W[k] || 0); });
      let total = sum / Math.max(1, tw) - g.flinches * 0.5;
      if (!out) total = Math.min(total, 30);
      Object.keys(parts).forEach(k => { parts[k] = Math.round(parts[k]); });
      return {
        score: Math.round(clamp(total, 0, 100)), parts,
        located: found >= N, method, falses: g.pr.falses, film: g.film.used ? (film && film.id) || true : false,
        disinfected: !g.skipped[2] && g.io.cov >= 0.9, coverage: +g.io.cov.toFixed(3), backtracks: g.io.back,
        incision: { length: Math.round(L), ideal: Math.round(c.ideal), depth: c.deepMax || c.blade, covered: c.covered, extensions: c.ext, muscle: c.muscle },
        extracted: g.xt.out.slice(), left: this.remaining().map(f => f.id), slips: g.xt.slips, misses: g.xt.misses, tears: g.ex.tears,
        haemostasis: !!g.done[6], bleedEnd: +bEnd.toFixed(2),
        sutured: !g.skipped[7] && closed >= 0.99, stitches: list.length, sections: SN, closed: +closed.toFixed(3), stitchQ: Math.round(avgQ), evenQ: Math.round(evenQ), sutMisses: g.sut.misses,
        dressed: !!(D && stuck >= cfg.stuckDone * 0.95), stuck: +stuck.toFixed(3), cover: +cover.toFixed(3),
        bloodLoss: Math.round(g.loss), gauze: g.gz.used, suctionMl: Math.round(g.su.ml),
        flinches: g.flinches, seconds: Math.round(g.t),
        skipped: Object.keys(g.skipped).map(Number),
      };
    },
    finish() {
      const g = this.g;
      if (this.finished) return;
      this.finished = true;
      this.stopActions();
      this.S.tools.use(null);
      this.stage.classList.remove('grab', 'grabbing');
      this.devEl.classList.remove('on');
      this.filmEl.classList.remove('on');
      this.S.markers.clear();
      const res = this.computeResult();
      this.result = res;
      setTimeout(() => {
        if (!this.alive || this.g !== g) return;
        this.showResult(res, null);
        NZA.post('bullet:finish', res).then(r => {
          if (!this.alive) return;
          if (r && r.outcome) this.showOutcome(r.outcome);
          else if (r && r.ok === false) this.showOutcome({ error: r.msg || T('err_save', 'The result could not be saved.') });
        });
      }, 650);
    },
    feedback(res) {
      const out = [];
      const N = res.extracted.length + res.left.length;
      if (res.method === 'xray') out.push(['ok', T('fbk_xray', 'Located on the X-ray before cutting.')]);
      else if (res.method === 'probe') out.push([res.falses ? 'warn' : 'ok', res.falses ? T('fbk_probe_false', 'Probed it out — with %s false passage(s).', res.falses) : T('fbk_probe', 'Found it with the probe along the track.')]);
      else if (res.method === 'none') out.push(['bad', T('fbk_blind', 'Cut without locating the fragment first.')]);
      if (res.skipped.includes(2)) out.push(['bad', T('fbk_noprep', 'No skin prep — high risk of infection.')]);
      else if (res.backtracks) out.push(['warn', T('fbk_backtrack', 'The swab went back over the centre %s time(s).', res.backtracks)]);
      if (res.incision.muscle) out.push(['bad', T('fbk_muscle', 'The blade went into the muscle (%s mm deep).', res.incision.depth)]);
      if (res.incision.length > res.incision.ideal * 1.4) out.push(['warn', T('fbk_long', 'Incision %s mm — about %s would have done.', res.incision.length, res.incision.ideal)]);
      if (res.slips) out.push(['warn', T('fbk_slips', 'The fragment slipped %s time(s) — pull slower.', res.slips)]);
      if (res.left.length) out.push(['warn', T('fbk_left', '%s of %s fragment(s) left in the wound.', res.left.length, N)]);
      else out.push(['ok', N > 1 ? T('fbk_all', 'All %s fragments removed.', N) : T('fbk_one', 'Projectile removed in one piece.')]);
      if (!res.haemostasis) out.push(['warn', T('fbk_bleed', 'Closed while still bleeding %s mL/min.', f1(res.bleedEnd))]);
      if (res.skipped.includes(7)) out.push(['warn', T('fbk_open', 'The incision was left open under the dressing.')]);
      else if (res.stitchQ < 70) out.push(['warn', T('fbk_stitch', 'Bites and spacing of the stitches could be cleaner.')]);
      out.push([res.bloodLoss >= 250 ? 'bad' : res.bloodLoss >= 120 ? 'warn' : 'ok', T('fbk_loss', 'Estimated blood loss %s mL.', res.bloodLoss)]);
      return out.slice(0, 7);
    },
    showResult(res, outcome) {
      this.resultShown = true;
      if (this.pp) { this.pp.destroy(); this.pp = null; }
      this.planEl.style.display = 'none'; this.notesEl.style.display = 'none';
      this.devEl.classList.remove('on'); this.filmEl.classList.remove('on');
      this.tags.innerHTML = ''; this.tagsHtml = '';
      const score = outcome && outcome.score !== undefined ? outcome.score : res.score;
      const grade = (outcome && outcome.grade) || (score >= 95 ? 'S' : score >= 85 ? 'A' : score >= 72 ? 'B' : score >= 58 ? 'C' : score >= 40 ? 'D' : 'F');
      const inj = this.inj || {};
      const N = res.extracted.length + res.left.length;
      const P = res.parts;
      const rows = [
        [T('r_locate', 'Locate'), res.method === 'xray' ? T('r_xray', 'X-ray') : res.method === 'probe' ? T('r_probe', 'Probe') : res.method === 'palpate' ? T('r_palp', 'Palpation') : T('none', 'None'), res.falses ? T('r_false', '%s false passage(s)', res.falses) : '', P.locate],
        [T('r_disinfect', 'Disinfect'), res.skipped.includes(2) ? T('skipped', 'Skipped') : `${Math.round(res.coverage * 100)}%`, T('r_cover', 'covered'), P.disinfect],
        [T('r_incise', 'Incision'), `${res.incision.length} mm`, T('r_incise_sub', 'aim %s · %s mm deep', res.incision.ideal, res.incision.depth), P.incise],
        [T('r_expose', 'Exposure'), res.tears ? T('r_tears', '%s tear(s)', res.tears) : T('r_clean', 'Clean'), '', P.expose],
        [T('r_extract', 'Extraction'), `${res.extracted.length}/${N}`, res.slips ? T('r_slips', '%s slip(s)', res.slips) : T('r_noslip', 'no slips'), P.extract],
        [T('r_haemo', 'Haemostasis'), `${f1(res.bleedEnd)}`, T('u_mlmin', 'mL/min'), P.haemostasis],
        [T('r_suture', 'Closure'), res.skipped.includes(7) ? T('r_open', 'Left open') : `${res.stitches}`, res.skipped.includes(7) ? '' : T('r_stitches', 'stitches · %s% even', res.evenQ), P.suture],
        [T('r_dressing', 'Dressing'), `${Math.round(res.cover * 100)}%`, T('r_dressing_sub', 'covered · %s% stuck', Math.round(res.stuck * 100)), P.dressing],
      ];
      const tone = v => (v >= 75 ? '' : v >= 45 ? 'amber' : 'red');
      const fb = this.feedback(res);
      const waiting = !outcome;
      const err = outcome && outcome.error;
      this.canClose = !waiting;
      const lost = Math.round(res.bloodLoss);
      this.resWrap.innerHTML = `
        <div class="bx-result nza-hud solid nza-pop ${score < 58 ? 'low' : ''}">
          <div class="rh"><span class="grade g-${esc(grade)}">${esc(grade)}</span>
            <div><h3>${esc(res.left.length ? T('r_title_part', 'Partly extracted') : T('r_title', 'Projectile removed'))}</h3><p>${esc(inj.label || '')} · ${esc(inj.regionLabel || '')} · ${esc(NZA.fmt.time(res.seconds))}</p></div>
            <div class="rk"><span>${esc(T('r_loss', 'Blood loss'))}</span><b class="${lost >= 250 ? 'red' : lost >= 120 ? 'amber' : ''}">${lost}<i>mL</i></b></div>
            <div class="sc"><b>${esc(score)}</b><span>${esc(T('r_score', 'Score'))}</span></div></div>
          <table>${rows.map(r => `<tr><td class="k">${esc(r[0])}</td><td class="d">${esc(r[1])}<i>${esc(r[2])}</i></td><td class="m">${NZA.ui.meterHTML({ value: r[3] / 100, tone: tone(r[3]) })}</td><td class="n">${esc(r[3])}</td></tr>`).join('')}</table>
          <ul class="fb">${fb.map(f => `<li class="${f[0]}">${esc(f[1])}</li>`).join('')}</ul>
          ${outcome && outcome.msg ? `<div class="msg">${esc(outcome.msg)}</div>` : ''}
          ${err ? `<div class="msg err">${esc(err)}</div>` : ''}
          <div class="act">${waiting ? `<span class="wait"><span class="ring"></span>${esc(T('r_saving', 'Saving the procedure…'))}</span>` : ''}
            <button class="pp-done" ${waiting ? 'disabled style="opacity:.45;pointer-events:none"' : ''}><kbd>Enter</kbd>${esc(T('done', 'Done'))}</button></div>
        </div>`;
      const btn = this.resWrap.querySelector('.pp-done');
      if (btn) btn.onclick = () => { if (this.canClose) this.closeNow(); };
    },
    showOutcome(o) {
      if (!this.result) return;
      this.showResult(this.result, o || {});
      if (!o.error) this.snd('success');
    },
    abort() {
      if (this.finished) { if (this.canClose) this.closeNow(); return; }
      NZA.post('bullet:abort', {});
      NZA.close('bullet');
    },
    exitBay() {
      if (this.finished && !this.canClose) return;
      NZA.post('bullet:exitBay', {});
      if (!NZA.inGame) NZA.close('bullet');
    },
    closeNow() { NZA.close('bullet'); },

    /* ═════════════ no WebGL: short manual fallback ═════════════ */
    fallback() {
      this.loadEl.classList.add('out');
      const inj = this.inj || DEMO.injury;
      const frs = (this.d.fragments || []).map(f => String(f.id));
      this.g = null;
      this.planEl.style.display = 'none';
      this.pp = NZA.ui.ProcPanel(this.ui, {
        step: 1, total: 1, tag: T('tag', 'Bullet extraction'), title: T('fbk_title', 'Removing the projectile'),
        text: T('fbk_text', '3D view unavailable on this client — the fragment is removed with a standard technique.'),
        stats: [{ label: T('st_site', 'Site'), value: inj.regionLabel || inj.region || '', small: true }, { label: T('st_left', 'Retained'), value: String(frs.length || 1) }],
        wide: { label: T('w_progress', 'Progress'), value: '0', unit: '%', meter: { value: 0 } },
        tools: [], abort: { label: T('hold_abort', 'Hold to abort'), key: 'ESC', seconds: 1.2 }, onAbort: () => this.abort(),
      });
      const dur = Math.max(8, +(this.cfg && this.cfg.fallbackTime) || 18);
      let t = 0;
      this.fallbackTimer = setInterval(() => {
        t += 0.25;
        if (this.pp) this.pp.wide({ value: String(Math.round(Math.min(1, t / dur) * 100)), meter: { value: Math.min(1, t / dur) } });
        if (t >= dur) {
          clearInterval(this.fallbackTimer); this.fallbackTimer = null;
          const parts = { locate: 60, disinfect: 60, incise: 60, expose: 60, extract: 60, haemostasis: 60, suture: 60, dressing: 60 };
          const res = { score: 60, parts, located: true, method: 'probe', falses: 0, film: false, disinfected: true, coverage: 1, backtracks: 0,
            incision: { length: 24, ideal: 24, depth: 6, covered: true, extensions: 0, muscle: false }, extracted: frs, left: [], slips: 0, misses: 0, tears: 0,
            haemostasis: true, bleedEnd: 1, sutured: true, stitches: 3, sections: 3, closed: 1, stitchQ: 60, evenQ: 60, sutMisses: 0,
            dressed: true, stuck: 1, cover: 1, bloodLoss: 90, gauze: 1, suctionMl: 0, flinches: 0, seconds: Math.round(t), skipped: [], fallback: true };
          this.result = res; this.finished = true; this.inj = inj;
          this.showResult(res, null);
          NZA.post('bullet:finish', res).then(r => { if (r && r.outcome) this.showOutcome(r.outcome); });
        }
      }, 250);
    },

    /* ═════════════ demo automation (browser preview / screenshots) ═════════════
       NZA.apps.bullet.demoTo('probe'|'located'|'film'|'disinfect'|'incise'|'cut'|'expose'|'extract'|'pull'|'control'|'suture'|'dressing'|'done') */
    demoTo(stage) {
      const S = this.S, g = this.g;
      if (!S || !g) return false;
      S.stop();
      const sim = (sec, fn) => { const n = Math.ceil(sec * 30); for (let i = 0; i < n; i++) { if (fn) fn(i / n, i); S.step(1 / 30, false); } };
      const aim = uv => { const p = S.project(uv); S.pointer.x = p.x; S.pointer.y = p.y; this.mx = p.x * window.innerWidth; this.my = p.y * window.innerHeight; };
      const press = () => this.down({ button: 0 }), release = () => this.up({ button: 0 });
      const done = () => { S.start(); return true; };
      const f0 = this.frags[0];
      // 1 locate
      if (stage === 'film') { this.toggleFilm(); return done(); }
      this.useTool('probe');
      for (const f of this.frags) {
        if (f.found) continue;
        aim(this.entryUv); sim(0.1); press();
        const cut = stage === 'probe' && f === f0;
        sim(cut ? 1.6 : 4.5, k => { const kk = clamp(g.pr.depth / f.depth, 0, 1); aim(S.stToUv(f.x * kk * MM, f.y * kk * MM)); void k; });
        if (cut) { aim(S.stToUv(f.x * 0.9 * MM, f.y * 0.1 * MM)); sim(0.2); return done(); }
        release(); sim(0.3);
      }
      clearTimeout(this.stepTimer); if (g.step === 1) this.enterStep(2);
      if (stage === 'located') { sim(0.6); return done(); }
      // 2 disinfect: spiral outward
      const ctr = S.uvToST(g.io.center), rr = g.io.radius * MM;
      aim(g.io.center); sim(0.05); press();
      const spins = stage === 'disinfect' ? 3.5 : 9;
      sim(spins * 0.9, k => { const a = k * spins * TAU, r = rr * (0.05 + k * 1.02); aim(S.stToUv(ctr[0] + Math.cos(a) * r, ctr[1] + Math.sin(a) * r)); });
      if (stage === 'disinfect') return done();
      release(); sim(0.2);
      if (!g.done[2]) { g.io.cov = 1; this.completeStep(2, ''); }
      clearTimeout(this.stepTimer); if (g.step === 2) this.enterStep(3);
      if (stage === 'incise') { sim(0.8); aim(this.cutCentre()); sim(0.1); return done(); }
      // 3 incise across all fragments
      const pts = this.frags.map(f => [f.x, f.y]);
      let ax = 1, ay = 0.15;
      if (pts.length > 1) { const a = pts[0], b = pts[pts.length - 1]; ax = b[0] - a[0]; ay = b[1] - a[1]; }
      const al = Math.hypot(ax, ay) || 1; ax /= al; ay /= al;
      let mn = Infinity, mx = -Infinity, cx = 0, cy = 0;
      pts.forEach(p => { const u = p[0] * ax + p[1] * ay; mn = Math.min(mn, u); mx = Math.max(mx, u); cx += p[0]; cy += p[1]; });
      cx /= pts.length; cy /= pts.length;
      const half = Math.max((mx - mn) / 2 + 2, g.cut.ideal / 2);
      const uMid = (mn + mx) / 2, offU = uMid - (cx * ax + cy * ay);
      const A = [cx + ax * (offU - half), cy + ay * (offU - half)], B = [cx + ax * (offU + half), cy + ay * (offU + half)];
      this.useTool('scalpel');
      aim(S.stToUv(A[0] * MM, A[1] * MM)); sim(0.05); press();
      const part = stage === 'cut' ? 0.6 : 1;
      sim(1.4 * part, k => aim(S.stToUv(lerp(A[0], B[0], k * part) * MM, lerp(A[1], B[1], k * part) * MM)));
      if (stage === 'cut') return done();
      release(); sim(0.2);
      clearTimeout(this.stepTimer); if (g.step === 3) this.enterStep(4);
      // 4 expose: spread, suction
      this.spreadKey(true); sim(stage === 'expose' ? 0.7 : 1.15); this.spreadKey(false);
      sim(2.5);
      if (stage === 'expose') { this.useTool('suction'); aim(this.cutCentre()); sim(0.1); press(); sim(0.4, k => aim(g.cut.w.at(0.3 + k * 0.4).uv)); return done(); }
      this.useTool('suction');
      for (const f of this.frags) { aim(f.uv); sim(0.05); press(); sim(1.2, k => { const st = S.uvToST(f.uv); aim(S.stToUv(st[0] + Math.cos(k * 12) * 0.002, st[1] + Math.sin(k * 12) * 0.002)); }); release(); }
      sim(0.1);
      if (g.step === 4 && !g.done[4]) { this.remaining().forEach(f => { f.exposed = true; }); this.completeStep(4, ''); }
      clearTimeout(this.stepTimer); if (g.step === 4) this.enterStep(5);
      if (stage === 'extract') { this.useTool('forceps'); aim(f0.uv); sim(0.3); return done(); }
      // 5 extract each, slowly
      this.useTool('forceps');
      for (const f of this.frags) {
        if (f.out) continue;
        this.useTool('suction'); aim(f.uv); sim(0.05); press(); sim(0.6); release();
        this.useTool('forceps');
        aim(f.uv); sim(0.1); press();
        if (f.lodge > 0) { for (let r = 0; r < 4; r++) { this.rock(r % 2 ? 1 : -1); sim(0.1); } }
        const pull = stage === 'pull' && f === f0;
        const y0 = this.my, total = window.innerHeight * this.cfg.pullDist * (pull ? 0.55 : 1.05);
        sim(pull ? 2.4 : 4.2, k => { this.my = y0 + total * k; });
        if (pull) return done();
        release(); sim(0.7);
      }
      clearTimeout(this.stepTimer); if (g.step === 5) this.enterStep(6);
      // 6 control: gauze pressure on the bleeder
      this.useTool('gauze');
      aim(this.bleederUv()); sim(0.05); press();
      sim(stage === 'control' ? 3 : 14, () => aim(this.bleederUv()));
      if (stage === 'control') return done();
      release(); sim(0.2);
      if (!g.done[6]) { g.bl.rate = 0.6; g.bl.boost = 0; this.completeStep(6, ''); }
      clearTimeout(this.stepTimer); if (g.step === 6) this.enterStep(7);
      // 7 suture
      const w = g.cut.w, N = g.sut.N, bite = this.cfg.bite;
      const nSt = stage === 'suture' ? Math.max(1, N - 1) : N;
      for (let i = 0; i < nSt; i++) {
        const tN = (i + 0.5) / N;
        aim(w.edge(tN, this.near, bite * MM)); sim(0.05); press();
        const b = w.edge(tN, -this.near, bite * MM);
        sim(0.45, k => { const a = w.edge(tN, this.near, bite * MM); aim([lerp(a[0], b[0], k), lerp(a[1], b[1], k)]); });
        aim(b); sim(0.03); release(); sim(0.1);
      }
      if (stage === 'suture') { sim(0.3); return done(); }
      clearTimeout(this.stepTimer); if (g.step === 7) this.enterStep(8);
      sim(0.6);
      if (stage === 'dressing') { aim(g.dr.restUv); return done(); }
      // 8 dressing: carry the near edge over, release, rub
      const D = g.dr.D, nrm = g.dr.nrm, tg = g.dr.target, dh = D.size[1], near = this.near || 1;
      const rest = S.uvToST(g.dr.restUv);
      const e0 = [rest[0] + nrm[0] * near * (dh / 2 - 0.0015), rest[1] + nrm[1] * near * (dh / 2 - 0.0015)];
      const e1 = [tg[0] + nrm[0] * near * (dh / 2 - 0.0015), tg[1] + nrm[1] * near * (dh / 2 - 0.0015)];
      aim(S.stToUv(e0[0], e0[1])); sim(0.05); press();
      sim(0.8, k => aim(S.stToUv(lerp(e0[0], e1[0], k), lerp(e0[1], e1[1], k))));
      release(); sim(1.4);
      press();
      const dir = w.at(0.5).dir, hw = [D.size[0] / 2 - 0.004, D.size[1] / 2 - 0.004];
      for (let k = 0; k < 8 && !g.done[8]; k++) {
        sim(2, q => { const x = Math.sin(q * Math.PI * 6 + k) * hw[0], y = Math.sin(q * Math.PI * 2 + k * 1.3) * hw[1]; aim(S.stToUv(tg[0] + dir[0] * x + nrm[0] * y, tg[1] + dir[1] * x + nrm[1] * y)); });
      }
      release(); sim(0.3);
      return done();
    },
  });

  // uv → patch metres (helper for the result maths)
  function S2(S, uv) { return S.uvToST(uv); }
})();
