// Product builders shared by the item pictures and the tool-belt pictures.
import {
  THREE, V3, deg, mat, mesh, group, rbox, lathe, cyl, rcyl, tube, strap, pillow, extrude, rrectShape, rrectPath, circlePath,
  wrapLabel, decal, canvasTex, txt, rr, NT, clearMat, cross, starOfLife, barcode, datamatrix, finePrint, helix, curve, rng, fbm,
} from '../lib.js';
import { drugLabel, boxFront } from '../labels.js';
import { vial, roll, sachet, fluidBag, tubingCoil, hemostat, scalpel, thumbForceps, sutureNeedle, ivCannula, hypoNeedle, syringe, card, TAU } from '../parts.js';

export const TEAL = '#0c8a83';

/* ── elastic crepe bandage roll with a clip ── */
export function bandageRoll({ r = 2.3, w = 7.5, tail = 6.5, color = 0xdcc8a6, line = '#2f6fbf' } = {}) {
  const stripe = canvasTex(512, 256, (g, W, H) => {
    g.fillStyle = '#' + new THREE.Color(color).getHexString(); g.fillRect(0, 0, W, H);
    g.fillStyle = 'rgba(255,255,255,.18)'; g.fillRect(0, 0, W, H * 0.06); g.fillRect(0, H * 0.94, W, H * 0.06);
    if (line) { g.fillStyle = line; g.fillRect(0, H * 0.485, W, H * 0.03); }
  });
  const g = roll({ r, w, color, tail, stripe, core: 0.22 });
  // tail strip: re-map the stripe onto its top face (strap v ≈ 0.25 there)
  const tailMesh = g.children[g.children.length - 1];
  const tm = stripe.clone(); tm.wrapS = tm.wrapT = THREE.RepeatWrapping; tm.repeat.set(1 / (TAU * r), 1); tm.offset.set(0, -0.25); tm.needsUpdate = true;
  tailMesh.material = mat.matte(0xffffff, { map: tm, roughness: 0.95, normalMap: NT.crepe([1 / (TAU * r) * 3, 1]), normalScale: new THREE.Vector2(0.7, 0.7) });
  g.children.forEach(c => { if (c.geometry.type === 'CylinderGeometry') c.material.normalMap = NT.crepe([3, 1]); });
  // two-claw elastic clip near the end of the tail
  if (tail) {
    const cx = r * 0.35 + tail - 1.2, y = 0.12;
    const clip = group([
      mesh(rbox(0.9, 0.05, 2.4, 0.02, 1), mat.matte(0xe7d9bf, { normalMap: NT.crepe([1, 1]) }), { pos: [0, 0.03, 0] }),
      ...[-1, 1].map(s => mesh(rbox(0.75, 0.07, 0.62, 0.05, 2), mat.satin({ roughness: 0.25 }), { pos: [0, 0.06, s * 1.0] })),
      ...[-1, 1].flatMap(s => [-0.25, 0, 0.25].map(dx => mesh(new THREE.ConeGeometry(0.05, 0.16, 6), mat.steel(), { pos: [dx, 0.04, s * 1.32], rot: [s * Math.PI / 2, 0, 0] }))),
    ], { pos: [cx, y, 0] });
    g.add(clip);
  }
  return g;
}

/* ── folded gauze pads ── */
export function gauzeTex() {
  return canvasTex(512, 512, (g, W) => {
    g.fillStyle = '#fbfbf8'; g.fillRect(0, 0, W, W);
    g.strokeStyle = 'rgba(150,150,140,.35)'; g.lineWidth = 1.4;
    for (let i = 0; i < W; i += 8) { g.beginPath(); g.moveTo(i, 0); g.lineTo(i + Math.sin(i) * 1.5, W); g.stroke(); g.beginPath(); g.moveTo(0, i); g.lineTo(W, i + Math.cos(i) * 1.5); g.stroke(); }
  }, { repeat: [2, 2] });
}
export function gauzePad({ w = 10, d = 10, t = 0.45, fold = true } = {}) {
  const m = mat.matte(0xffffff, { map: gauzeTex(), roughness: 1, normalMap: NT.gauze([3, 3]), normalScale: new THREE.Vector2(0.9, 0.9) });
  const parts = [mesh(rbox(w, t, d, t * 0.45, 3), m, { pos: [0, t / 2, 0] })];
  // fold lines (slightly raised layers)
  if (fold) parts.push(mesh(rbox(w * 0.98, t * 0.4, d * 0.48, t * 0.18, 2), m, { pos: [0, t + t * 0.15, -d * 0.24] }));
  return group(parts);
}
export function gauzeStack({ n = 3, w = 9, d = 9 } = {}) {
  const R = rng(5), parts = [];
  for (let i = 0; i < n; i++) { const p = gauzePad({ w, d, t: 0.42 }); p.position.set((R() - 0.5) * 0.8, i * 0.55, (R() - 0.5) * 0.8); p.rotation.y = (R() - 0.5) * 0.25; parts.push(p); }
  return group(parts);
}
// loose roll of open-weave gauze (packing)
export function gauzeRoll({ r = 2.4, w = 6, tail = 6 } = {}) {
  const end = canvasTex(512, 512, (g, W) => {
    g.fillStyle = '#f7f7f2'; g.beginPath(); g.arc(W / 2, W / 2, W / 2, 0, TAU); g.fill();
    g.strokeStyle = 'rgba(120,120,110,.25)'; g.lineWidth = 2;
    for (let i = 0; i < 32; i++) { g.beginPath(); g.arc(W / 2, W / 2, W / 2 * (0.25 + 0.75 * i / 32), 0, TAU); g.stroke(); }
    g.fillStyle = '#ddd9cc'; g.beginPath(); g.arc(W / 2, W / 2, W * 0.12, 0, TAU); g.fill();
  });
  const g = roll({ r, w, color: 0xf8f8f3, tail, normal: 'gauze', end, rough: 1, core: 0.25 });
  g.children.forEach(c => { if (c.material && c.geometry.type !== 'CircleGeometry') { c.material.map = gauzeTex(); c.material.map.repeat.set(4, 2); } });
  return g;
}

/* ── island dressing (adhesive border + pad), optional peel liner ── */
export function islandDressing({ w = 10, d = 8, liner = true } = {}) {
  const bTex = canvasTex(512, 512 * d / w, (g, W, H) => { g.fillStyle = '#f1ece1'; g.fillRect(0, 0, W, H); g.strokeStyle = 'rgba(40,110,190,.55)'; g.setLineDash([10, 8]); g.lineWidth = 4; g.strokeRect(W * 0.17, H * 0.2, W * 0.66, H * 0.6); });
  const border = new THREE.MeshPhysicalMaterial({ map: bTex, roughness: 0.85, normalMap: NT.foam([4, 4]), normalScale: new THREE.Vector2(0.3, 0.3), sheen: 0.4, sheenColor: new THREE.Color(0xffffff) });
  const padTex = canvasTex(256, 256, (g, W) => { g.fillStyle = '#fbfbfb'; g.fillRect(0, 0, W, W); g.fillStyle = 'rgba(0,0,0,.05)'; for (let y = 0; y < W; y += 6) for (let x = (y / 6) % 2 * 3; x < W; x += 6) g.fillRect(x, y, 2, 2); }, { repeat: [3, 3] });
  const parts = [
    mesh(rbox(w, 0.08, d, 0.04, 2), border, { pos: [0, 0.06, 0] }),
    mesh(rbox(w * 0.56, 0.42, d * 0.5, 0.18, 3), mat.matte(0xffffff, { map: padTex, roughness: 0.95, normalMap: NT.gauze([2, 2]), normalScale: new THREE.Vector2(0.4, 0.4) }), { pos: [0, 0.24, 0] }),
  ];
  if (liner) {
    // printed release liner tabs underneath, one corner peeled up
    parts.push(mesh(rbox(w * 1.1, 0.03, d * 1.03, 0.01, 1), mat.matte(0x4f9fd6, { roughness: 0.45 }), { pos: [w * 0.05, 0.015, 0] }));
  }
  return group(parts);
}

/* ── printed sachets ── */
export function sachetTex({ title, line2 = '', line3 = '', band = TEAL, bg = '#f6f6f2', icon = null, w = 1024, h = 1200, dark = false, seed = 7, foil = false } = {}) {
  return canvasTex(w, h, (g) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    // crimped seam band
    const s = h * 0.065;
    g.fillStyle = foil ? '#c9ced2' : '#e9e8e2'; g.fillRect(0, 0, w, s); g.fillRect(0, h - s, w, s); g.fillRect(0, 0, s, h); g.fillRect(w - s, 0, s, h);
    g.strokeStyle = 'rgba(0,0,0,.08)'; g.lineWidth = 2; for (let x = 0; x < w; x += 10) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, s); g.moveTo(x, h - s); g.lineTo(x, h); g.stroke(); }
    g.fillStyle = band; g.fillRect(s, s, w - 2 * s, h * 0.16);
    txt(g, 'STERILE', w * 0.12, s + h * 0.105, { size: h * 0.055, weight: 800, color: '#fff', spacing: 6 });
    const ink = dark ? '#f4f6f7' : '#14191d';
    txt(g, title, w * 0.12, h * 0.4, { size: h * 0.085, weight: 800, color: ink, max: w * 0.76 });
    if (line2) txt(g, line2, w * 0.12, h * 0.48, { size: h * 0.05, weight: 600, color: band, max: w * 0.76 });
    if (line3) txt(g, line3, w * 0.12, h * 0.545, { size: h * 0.034, weight: 400, color: dark ? '#cfd6da' : '#444', max: w * 0.76 });
    if (icon) icon(g, w, h);
    finePrint(g, w * 0.12, h * 0.8, w * 0.45, 3, { h: h * 0.012, gap: h * 0.018, seed, color: dark ? 'rgba(255,255,255,.4)' : 'rgba(0,0,0,.35)' });
    barcode(g, w * 0.62, h * 0.78, w * 0.26, h * 0.08, seed, dark ? '#eef' : '#111');
  });
}

/* ── saline irrigation bottle (squeezable, twist-off nozzle) ── */
export function salineBottle({ r = 2.4, h = 10.5, theta = 0 } = {}) {
  const body = mat.plastic(0xf3f5f6, { roughness: 0.45, clearcoat: 0.2 });
  const prof = [[0.001, 0], [r * 0.85, 0], [r * 0.97, 0.08], [r, 0.25], [r, h * 0.72]];
  for (let i = 1; i <= 10; i++) { const a = (i / 10) * Math.PI / 2; prof.push([r * 0.42 + r * 0.58 * Math.cos(a), h * 0.72 + h * 0.15 * Math.sin(a)]); }
  prof.push([r * 0.42, h * 0.92], [0.001, h * 0.92]);
  const parts = [mesh(lathe(prof, { seg: 72 }), body)];
  // ribbed twist cap + nozzle
  parts.push(mesh(rcyl(r * 0.5, h * 0.09, 0.08, { y: h * 0.9 }), mat.plastic(0x1f62c4, { roughness: 0.4, normalMap: NT.ribs([1, 14]), normalScale: new THREE.Vector2(0.5, 0.5) })));
  parts.push(mesh(lathe([[r * 0.34, 0], [r * 0.3, h * 0.05], [r * 0.12, h * 0.1], [r * 0.08, h * 0.13], [0.001, h * 0.135]], { seg: 40 }), mat.plastic(0x1f62c4, { roughness: 0.35 }), { pos: [0, h * 0.99, 0] }));
  const lab = drugLabel({ w: 1024, h: 420, name: '0.9% SODIUM CHLORIDE', strength: 'IRRIGATION  ·  250 mL', sub: 'STERILE  ·  NOT FOR INJECTION  ·  SINGLE USE', band: '#1f62c4', bandText: 'IRRIGATION SOLUTION', seed: 31, window: 1 });
  parts.push(wrapLabel(r + 0.02, h * 0.14, h * 0.66, lab, { theta, len: TAU * 0.56, focus: 0.37 }));
  return group(parts);
}

/* ── contrast medium bottle ── */
export function contrastBottle({ theta = deg(30) } = {}) {
  const lab = drugLabel({ w: 1024, h: 380, name: 'CONTRAST MEDIUM', strength: '350 mg I/mL  ·  100 mL', sub: 'IODINATED  ·  FOR INTRAVASCULAR USE', band: '#e0a21a', bandText: 'X-RAY CONTRAST', seed: 41, window: 1 });
  return vial({ r: 2.5, h: 9.5, cap: 0x2a6fd6, liquid: 0xf2df9a, fill: 0.56, label: lab, theta, labelY0: 0.1, labelY1: 0.5 });
}

/* ── IV / blood bags ── */
export function salineBagLabel() {
  return canvasTex(512, 640, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    txt(g, '0.9% SODIUM', w * 0.06, h * 0.12, { size: 52, weight: 800, color: '#1b4fa0' });
    txt(g, 'CHLORIDE', w * 0.06, h * 0.21, { size: 52, weight: 800, color: '#1b4fa0' });
    txt(g, 'INTRAVENOUS INFUSION', w * 0.06, h * 0.29, { size: 26, weight: 600, color: '#1b4fa0' });
    g.fillStyle = '#1b4fa0'; g.fillRect(w * 0.06, h * 0.33, w * 0.88, 5);
    txt(g, '500 mL', w * 0.06, h * 0.45, { size: 70, weight: 800, color: '#1b4fa0' });
    finePrint(g, w * 0.06, h * 0.52, w * 0.6, 6, { h: 8, gap: 10, color: 'rgba(27,79,160,.75)', seed: 21 });
    barcode(g, w * 0.06, h * 0.78, w * 0.5, h * 0.1, 21, '#1b4fa0');
    g.fillStyle = '#1b4fa0';
    for (let i = 0; i <= 5; i++) { const y = h * 0.6 + i * h * 0.065; g.fillRect(w * 0.84, y, w * 0.1, 4); txt(g, String(100 * (5 - i)), w * 0.82, y + 8, { size: 20, weight: 600, color: '#1b4fa0', align: 'right' }); }
  });
}
export function salineBag() {
  return fluidBag({ w: 10, h: 15, t: 2.6, fill: 0.88, label: salineBagLabel(), labelW: 0.8, labelH: 0.75, labelY: 0.5, portColors: [0x2f7fd8, 0xffffff] });
}
export function bloodLabel({ group: grp = 'O', rh = 'NEG', empty = false } = {}) {
  return canvasTex(512, 600, (g, w, h) => {
    g.fillStyle = '#fbfbf7'; rr(g, 0, 0, w, h, 18); g.fill();
    if (empty) {
      g.fillStyle = '#b3121f'; g.fillRect(0, 0, w, h * 0.13);
      txt(g, 'BLOOD COLLECTION BAG', w * 0.06, h * 0.09, { size: 30, weight: 800, color: '#fff', max: w * 0.88 });
      txt(g, '450 mL', w * 0.06, h * 0.3, { size: 76, weight: 800, color: '#16191d' });
      txt(g, 'CPDA-1 ANTICOAGULANT', w * 0.06, h * 0.4, { size: 28, weight: 600, color: '#b3121f' });
      finePrint(g, w * 0.06, h * 0.48, w * 0.8, 6, { h: 9, gap: 12, seed: 52 });
      barcode(g, w * 0.06, h * 0.78, w * 0.6, h * 0.12, 52);
      return;
    }
    g.fillStyle = '#b3121f'; g.fillRect(0, 0, w, h * 0.13);
    txt(g, 'RED BLOOD CELLS', w * 0.06, h * 0.09, { size: 32, weight: 800, color: '#fff' });
    barcode(g, w * 0.06, h * 0.17, w * 0.55, h * 0.09, 61);
    txt(g, 'UNIT 26-0418-73', w * 0.06, h * 0.31, { size: 22, weight: 600, color: '#222', font: '"JetBrains Mono", monospace' });
    g.fillStyle = '#16191d'; rr(g, w * 0.06, h * 0.36, w * 0.88, h * 0.34, 14); g.fill();
    txt(g, grp, w * 0.3, h * 0.64, { size: 170, weight: 800, color: '#fff', align: 'center' });
    txt(g, rh, w * 0.7, h * 0.52, { size: 64, weight: 800, color: '#fff', align: 'center' });
    txt(g, 'Rh D', w * 0.7, h * 0.63, { size: 26, weight: 600, color: '#d8dde0', align: 'center' });
    finePrint(g, w * 0.06, h * 0.75, w * 0.5, 4, { h: 8, gap: 10, seed: 62 });
    barcode(g, w * 0.62, h * 0.76, w * 0.32, h * 0.12, 63);
  });
}
export function bloodBag() {
  const b = fluidBag({ w: 10, h: 14, t: 2.8, fill: 0.92, liquid: 0x6d0710, liquidOpacity: 0.94, label: bloodLabel(), labelW: 0.7, labelH: 0.62, labelY: 0.48, ports: 3, portColors: [0xb3121f, 0xffffff, 0xffffff], filmColor: 0xfaf3f3 });
  // donor tubing segment, coiled and sealed
  b.add(tubingCoil({ r: 2.4, turns: 1.4, tubeR: 0.2, color: 0x7a0a14, clear: false, x: 0, z: 0 }));
  b.children[b.children.length - 1].rotation.x = Math.PI / 2;
  b.children[b.children.length - 1].position.set(-3.2, -1.2, 1.6);
  return b;
}

/* ── foil rescue blanket, folded ── */
export function foilBlanket({ w = 12, d = 9, t = 1.6 } = {}) {
  const gold = new THREE.MeshStandardMaterial({ color: 0xe0b45a, metalness: 1, roughness: 0.22, normalMap: NT.crinkle([1.5, 1.5]), normalScale: new THREE.Vector2(0.55, 0.55) });
  const silver = new THREE.MeshStandardMaterial({ color: 0xd9dde1, metalness: 1, roughness: 0.2, normalMap: NT.crinkle([1.2, 1.2]), normalScale: new THREE.Vector2(0.55, 0.55) });
  const parts = [];
  // stacked folds with slightly uneven edges
  const R = rng(9);
  for (let i = 0; i < 4; i++) parts.push(mesh(rbox(w - R() * 0.4, t / 4, d - R() * 0.4, 0.15, 2), i === 3 ? gold : (i % 2 ? silver : gold), { pos: [(R() - 0.5) * 0.25, t / 8 + i * t / 4, (R() - 0.5) * 0.25] }));
  // a corner flap folded open over the front edge
  const flap = [V3(w * 0.05, t + 0.05, -d * 0.1), V3(w * 0.15, t + 0.4, d * 0.35), V3(w * 0.22, t * 0.6, d * 0.62), V3(w * 0.3, 0.06, d * 0.82), V3(w * 0.45, 0.04, d * 1.0)];
  parts.push(mesh(strap(flap, w * 0.55, 0.04, { up: V3(1, 0, 0) }), gold));
  return group(parts);
}

/* ── chest x-ray film ── */
export function xrayTex() {
  return canvasTex(768, 896, (g, w, h) => {
    const bg = g.createRadialGradient(w / 2, h * 0.45, w * 0.1, w / 2, h * 0.45, w * 0.75);
    bg.addColorStop(0, '#2b3a48'); bg.addColorStop(1, '#0b1015');
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    // body outline + lungs (darker), mediastinum + heart (lighter)
    g.fillStyle = 'rgba(160,190,210,.18)'; g.beginPath(); g.ellipse(w / 2, h * 0.55, w * 0.42, h * 0.5, 0, 0, TAU); g.fill();
    g.fillStyle = 'rgba(5,10,16,.55)';
    g.beginPath(); g.ellipse(w * 0.32, h * 0.47, w * 0.15, h * 0.3, 0.08, 0, TAU); g.fill();
    g.beginPath(); g.ellipse(w * 0.68, h * 0.47, w * 0.15, h * 0.3, -0.08, 0, TAU); g.fill();
    g.fillStyle = 'rgba(190,215,230,.35)'; g.beginPath(); g.ellipse(w * 0.55, h * 0.62, w * 0.14, h * 0.13, 0.4, 0, TAU); g.fill();
    // spine
    g.fillStyle = 'rgba(210,228,238,.55)';
    for (let i = 0; i < 14; i++) { rr(g, w * 0.475, h * 0.1 + i * h * 0.058, w * 0.05, h * 0.048, 6); g.fill(); }
    // ribs
    g.strokeStyle = 'rgba(215,232,242,.62)'; g.lineWidth = 9; g.lineCap = 'round';
    for (let i = 0; i < 9; i++) {
      const y = h * 0.2 + i * h * 0.062;
      for (const s of [-1, 1]) { g.beginPath(); g.moveTo(w / 2 + s * w * 0.03, y); g.bezierCurveTo(w / 2 + s * w * 0.3, y - h * 0.07, w / 2 + s * w * 0.4, y + h * 0.02, w / 2 + s * w * 0.3, y + h * 0.1); g.stroke(); }
    }
    // clavicles + shoulders
    g.lineWidth = 14;
    for (const s of [-1, 1]) { g.beginPath(); g.moveTo(w / 2 + s * w * 0.05, h * 0.16); g.quadraticCurveTo(w / 2 + s * w * 0.22, h * 0.1, w / 2 + s * w * 0.4, h * 0.14); g.stroke(); }
    g.fillStyle = 'rgba(220,235,245,.4)'; for (const s of [-1, 1]) { g.beginPath(); g.ellipse(w / 2 + s * w * 0.43, h * 0.17, w * 0.06, h * 0.045, 0, 0, TAU); g.fill(); }
    // diaphragm
    g.fillStyle = 'rgba(200,220,232,.3)'; g.beginPath(); g.moveTo(w * 0.12, h); g.quadraticCurveTo(w * 0.3, h * 0.66, w / 2, h * 0.78); g.quadraticCurveTo(w * 0.72, h * 0.68, w * 0.88, h); g.fill();
    // marker + id strip
    g.fillStyle = '#f2f6f8'; txt(g, 'R', w * 0.08, h * 0.12, { size: 64, weight: 800, color: '#eef4f7' });
    g.fillStyle = 'rgba(240,244,246,.9)'; g.fillRect(w * 0.58, h * 0.03, w * 0.36, h * 0.07);
    txt(g, 'PA CHEST', w * 0.6, h * 0.075, { size: 26, weight: 700, color: '#1b2229' });
  });
}
export function xrayFilm({ w = 14, d = 17 } = {}) {
  const tex = xrayTex();
  const filmMat = new THREE.MeshPhysicalMaterial({ map: tex, roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.08 });
  const edge = clearMat({ color: 0x8fb2c8, roughness: 0.1, opacity: 0.55, lum: 0.6 });
  const geo = rbox(w, 0.06, d, 0.03, 1);
  const m = mesh(geo, [edge, edge, filmMat, edge, edge, edge]);
  m.position.y = 0.03;
  return group([m]);
}

/* ── embolisation coil (platinum, coiled into loops) on its pusher wire ── */
export function coilGeom({ R = 1.6, loops = 2.2, r = 0.2, wire = 0.045, turnsPerLoop = 46, lift = 0.5 } = {}) {
  const N = Math.ceil(loops * turnsPerLoop * 14), pts = [];
  const C = t => V3(Math.cos(t) * R, lift + (t / (loops * TAU)) * lift * 1.5, Math.sin(t) * R);
  for (let i = 0; i <= N; i++) {
    const t = (i / N) * loops * TAU, c = C(t);
    const T = C(t + 0.01).sub(c).normalize(), up = V3(0, 1, 0), B = V3().crossVectors(T, up).normalize(), Nn = V3().crossVectors(B, T);
    const a = t * turnsPerLoop;
    pts.push(c.add(Nn.multiplyScalar(Math.cos(a) * r)).add(B.multiplyScalar(Math.sin(a) * r)));
  }
  const cv = new THREE.CatmullRomCurve3(pts);
  return new THREE.TubeGeometry(cv, N, wire, 6, false);
}
export function emboCoil({ wire = true } = {}) {
  const pt = new THREE.MeshStandardMaterial({ color: 0xe9e6e0, metalness: 1, roughness: 0.18 });
  const parts = [mesh(coilGeom({}), pt)];
  if (wire) {
    // pusher wire leaving the coil and a clear introducer
    const wp = [V3(1.6, 0.5, 0), V3(3.2, 0.3, 0.6), V3(5.5, 0.2, 1.0), V3(8, 0.2, 1.3)];
    parts.push(mesh(tube(wp, 0.05, { radial: 8 }), mat.steel({ roughness: 0.25 })));
    parts.push(mesh(tube([V3(5.2, 0.22, 0.98), V3(8.6, 0.24, 1.36)], 0.16, { radial: 14, tubular: 8 }), clearMat({ color: 0xeaf4fa, roughness: 0.12, opacity: 0.35 }), { order: 3 }));
    parts.push(mesh(rcyl(0.3, 0.9, 0.08), mat.plastic(0x2e86d6), { pos: [8.8, 0.25, 1.4], rot: [0, -0.2, -Math.PI / 2] }));
  }
  return group(parts);
}

/* ── endotracheal tube (Magill curve), cuff, pilot line, 15 mm connector ── */
export function ett({ len = 22, inflated = true } = {}) {
  const pts = [];
  for (let i = 0; i <= 30; i++) { const t = i / 30, a = t * deg(85); pts.push(V3(Math.sin(a) * len * 0.62, 0.55, -(1 - Math.cos(a)) * len * 0.62 + 0)); }
  const cv = new THREE.CatmullRomCurve3(pts);
  const parts = [];
  parts.push(mesh(new THREE.TubeGeometry(cv, 160, 0.55, 28, false), clearMat({ color: 0x2c4654, spec: 0xe4f4fa, roughness: 0.06, opacity: 0.25, lum: 0.95, envMapIntensity: 1.6 }), { order: 4 }));
  // radiopaque line
  const lp = pts.map(p => p.clone().add(V3(0, 0.54, 0)));
  parts.push(mesh(tube(lp, 0.08, { radial: 6 }), mat.plastic(0x2f6fd8, { roughness: 0.4 })));
  // cuff near the tip
  const tip = cv.getPointAt(0.9), tdir = cv.getTangentAt(0.9);
  if (inflated) {
    const cuff = mesh(lathe([[0.56, 0], [0.95, 0.5], [1.08, 1.4], [0.95, 2.3], [0.56, 2.8]], { seg: 40, smooth: 30 }), clearMat({ color: 0x2c4654, spec: 0xe4f4fa, roughness: 0.08, opacity: 0.3, lum: 0.95 }), { order: 5 });
    cuff.position.copy(cv.getPointAt(0.86)); cuff.quaternion.setFromUnitVectors(V3(0, 1, 0), tdir);
    parts.push(cuff);
  }
  // bevelled tip
  const tp = cv.getPointAt(1);
  // 15 mm connector at the machine end
  const c0 = cv.getPointAt(0), cd = cv.getTangentAt(0).negate();
  const conn = mesh(lathe([[0.5, 0], [0.56, 0.2], [0.56, 1.0], [0.9, 1.1], [0.9, 1.5], [0.72, 1.6], [0.72, 2.8], [0.6, 2.9]], { seg: 40 }), mat.plastic(0xf3f5f6, { roughness: 0.35 }));
  conn.position.copy(c0); conn.quaternion.setFromUnitVectors(V3(0, 1, 0), cd);
  parts.push(conn);
  // pilot line + balloon + valve
  const pl0 = cv.getPointAt(0.2);
  const pl = [pl0, pl0.clone().add(V3(-1, 0.1, 2)), pl0.clone().add(V3(-2.5, 0.1, 4.2)), pl0.clone().add(V3(-3.5, 0.25, 5.6))];
  parts.push(mesh(tube(pl, 0.06, { radial: 8 }), clearMat({ color: 0xeaf4f8, roughness: 0.15, opacity: 0.5 }), { order: 4 }));
  const bal = mesh(lathe([[0.06, 0], [0.45, 0.4], [0.5, 1.0], [0.3, 1.5], [0.2, 1.6]], { seg: 32, smooth: 24 }), clearMat({ color: 0xf6fbff, roughness: 0.1, opacity: 0.35 }), { order: 4 });
  const pe = pl[3]; bal.position.copy(pe); bal.quaternion.setFromUnitVectors(V3(0, 1, 0), pl[3].clone().sub(pl[2]).normalize());
  parts.push(bal);
  const valve = mesh(rcyl(0.24, 1.0, 0.06), mat.plastic(0xf2f2f2, { roughness: 0.3 }));
  valve.position.copy(pe.clone().add(pl[3].clone().sub(pl[2]).normalize().multiplyScalar(1.55))); valve.quaternion.copy(bal.quaternion);
  parts.push(valve);
  return group(parts);
}

/* ── Yankauer suction tip + tubing ── */
export function yankauer({ lead = true } = {}) {
  const clear = clearMat({ color: 0x2a4a5c, spec: 0xe0f2fa, roughness: 0.06, opacity: 0.22, lum: 0.95, envMapIntensity: 1.6 });
  const pts = [V3(-9, 0.85, 0), V3(-3, 0.85, 0), V3(2, 0.85, 0), V3(4.6, 0.8, 0.2), V3(6.3, 0.62, 0.9), V3(7.2, 0.55, 1.9)];
  const parts = [mesh(tube(pts, 0.6, { radial: 28, tension: 0.4 }), clear, { order: 4 })];
  // ribbed grip + bulb tip with holes
  parts.push(mesh(new THREE.CylinderGeometry(0.72, 0.72, 5, 36, 1, true).rotateZ(Math.PI / 2).translate(-5.2, 0.85, 0), clearMat({ color: 0x2a4a5c, spec: 0xe0f2fa, roughness: 0.25, opacity: 0.3, lum: 0.9, normalMap: NT.ribs([1, 10]), normalScale: 0.8 }), { order: 4 }));
  parts.push(mesh(new THREE.SphereGeometry(0.72, 28, 18), clear, { order: 4, pos: [7.35, 0.58, 2.1], scale: [1, 0.9, 1.2] }));
  for (let k = 0; k < 4; k++) { const a = k / 4 * TAU; parts.push(mesh(new THREE.CircleGeometry(0.13, 12), mat.matte(0x1a2a33), { pos: [7.35 + Math.cos(a) * 0.62, 0.58 + Math.sin(a) * 0.35, 2.1 + 0.3], rot: [0, Math.cos(a) * 0.8, 0] })); }
  // thumb vent
  parts.push(mesh(new THREE.TorusGeometry(0.28, 0.08, 8, 24), clearMat({ color: 0x2a4a5c, spec: 0xe0f2fa, roughness: 0.1, opacity: 0.5 }), { pos: [-1.4, 1.45, 0], rot: [Math.PI / 2, 0, 0], order: 4 }));
  // connector + suction tubing curling back
  parts.push(mesh(rcyl(0.82, 1.8, 0.12), mat.plastic(0xf4f4f4, { roughness: 0.35 }), { pos: [-9.2, 0.85, 0], rot: [0, 0, Math.PI / 2] }));
  if (lead) {
    const tp = [V3(-10.8, 0.85, 0), V3(-13, 0.65, -0.6), V3(-14, 0.6, -3), V3(-12, 0.6, -5.2), V3(-8, 0.6, -5.2), V3(-5, 0.6, -4.2)];
    parts.push(mesh(tube(tp, 0.62, { radial: 20 }), clearMat({ color: 0x3d5c6a, spec: 0xe8f4f8, roughness: 0.2, opacity: 0.3, lum: 0.85, normalMap: NT.ribs([40, 1]), normalScale: 0.5 }), { order: 4 }));
  }
  return group(parts);
}

/* ── electric dermatome ── */
export function dermatome() {
  const body = mat.satin({ roughness: 0.3 });
  const parts = [];
  const hp = mesh(lathe([[0.001, 0], [1.3, 0], [1.45, 0.3], [1.5, 9], [1.35, 12], [1.1, 14], [0.7, 15.2], [0.001, 15.3]], { seg: 48, smooth: 50 }), body);
  hp.rotation.z = Math.PI / 2; hp.position.set(4, 1.5, 0);
  parts.push(hp);
  // grip band + switch
  parts.push(mesh(new THREE.CylinderGeometry(1.53, 1.53, 4, 40, 1, true).rotateZ(Math.PI / 2).translate(-3, 1.5, 0), mat.rubber(0x2a2e33, { normalMap: NT.ribs([1, 8]) })));
  parts.push(mesh(rbox(2.6, 0.5, 0.9, 0.2, 2), mat.plastic(0x2b6fd0), { pos: [-0.5, 3.0, 0] }));
  // cutting head: wide blade guard + width plate
  parts.push(mesh(rbox(3.2, 2.6, 8.2, 0.4, 3), mat.steel({ roughness: 0.25 }), { pos: [5.6, 1.3, 0] }));
  parts.push(mesh(rbox(1.0, 0.35, 8.6, 0.12, 2), mat.chrome(), { pos: [7.4, 0.25, 0] }));
  parts.push(mesh(rbox(1.6, 0.25, 7.6, 0.1, 2), mat.plastic(0x2b6fd0), { pos: [6.4, 2.7, 0] }));
  // cable
  parts.push(mesh(tube([V3(-11.2, 1.5, 0), V3(-13, 1.2, 0.3), V3(-15, 0.4, 2), V3(-14, 0.35, 5), V3(-10, 0.35, 5.8)], 0.32, { radial: 14 }), mat.rubber(0x26292d, { roughness: 0.5 })));
  return group(parts);
}

/* ── skin graft mesher (ridged cutting roller + crank) ── */
export function mesher() {
  const steel = mat.satin({ roughness: 0.28 });
  const parts = [];
  parts.push(mesh(rbox(14, 0.8, 9, 0.3, 3), steel, { pos: [0, 0.4, 0] }));
  for (const s of [-1, 1]) parts.push(mesh(rbox(1.2, 5, 9, 0.4, 3), steel, { pos: [s * 5.6, 3, 0] }));
  // ridged roller (rings) across the frame
  const ring = [];
  for (let i = 0; i < 20; i++) ring.push(new THREE.CylinderGeometry(1.5, 1.5, 0.22, 40).rotateZ(Math.PI / 2).translate(-4.4 + i * 0.46, 3.4, 0));
  parts.push(mesh(new THREE.CylinderGeometry(1.25, 1.25, 10.6, 40).rotateZ(Math.PI / 2).translate(0, 3.4, 0), mat.steel({ roughness: 0.3 })));
  ring.forEach(g => parts.push(mesh(g, mat.chrome({ roughness: 0.12 }))));
  // carrier tray sliding through
  parts.push(mesh(rbox(10.5, 0.15, 13, 0.05, 1), mat.plastic(0xf2f2ec, { roughness: 0.4 }), { pos: [0, 1.95, 1.2] }));
  // crank
  parts.push(mesh(cyl(0.3, 1.6), steel, { pos: [6.2, 3.4, 0], rot: [0, 0, -Math.PI / 2] }));
  parts.push(mesh(rbox(0.5, 4.4, 0.8, 0.2, 2), steel, { pos: [7.9, 1.8, 0] }));
  parts.push(mesh(rcyl(0.55, 2.2, 0.2), mat.plastic(0x2b2f34), { pos: [8.15, 0.2, 0], rot: [0, 0, -Math.PI / 2] }));
  return group(parts);
}

/* ── skin stapler (pistol grip) ── */
export function skinStapler() {
  const parts = [];
  const s = new THREE.Shape();
  s.moveTo(-4.5, 5); s.lineTo(3.6, 5); s.quadraticCurveTo(4.6, 5, 4.6, 4); s.lineTo(4.6, 2.6); s.lineTo(3.2, 1.4); s.lineTo(-1.2, 1.4); s.lineTo(-3.4, -3.2); s.quadraticCurveTo(-3.8, -4, -4.6, -3.6); s.lineTo(-5.6, -3.1); s.quadraticCurveTo(-6, -2.8, -5.8, -2.2); s.lineTo(-4.5, 5);
  const body = mesh(extrude(s, 2.2, { bevel: 0.35, bevelSeg: 4 }), mat.plastic(0xf1f2f2, { roughness: 0.35 }));
  parts.push(body);
  // dark grip insert + grey nose so the pistol shape reads at icon size
  const gr = new THREE.Shape(); gr.moveTo(-4.3, 3.6); gr.lineTo(-1.6, 1.6); gr.lineTo(-3.5, -2.8); gr.quadraticCurveTo(-3.9, -3.5, -4.6, -3.2); gr.lineTo(-5.4, -2.8); gr.lineTo(-4.3, 3.6);
  parts.push(mesh(extrude(gr, 2.36, { bevel: 0.2 }), mat.rubber(0x3a3f45, { roughness: 0.6 })));
  parts.push(mesh(rbox(1.6, 1.9, 2.0, 0.35, 3), mat.plastic(0x59616a, { roughness: 0.4 }), { pos: [4.3, 2.3, 0] }));
  const tr = new THREE.Shape();
  tr.moveTo(-0.6, 1.3); tr.lineTo(2.4, 1.3); tr.quadraticCurveTo(2.3, -1.2, 0.2, -3.3); tr.quadraticCurveTo(-0.6, -3.6, -0.9, -2.8); tr.lineTo(-0.6, 1.3);
  parts.push(mesh(extrude(tr, 2.0, { bevel: 0.3 }), mat.plastic(0x2b6fd0, { roughness: 0.3 })));
  // clear head with staples + counter window
  parts.push(mesh(rbox(1.0, 1.0, 1.6, 0.25, 3), clearMat({ color: 0x2c4654, spec: 0xe4f4fa, roughness: 0.06, opacity: 0.3, lum: 0.9 }), { pos: [5.2, 1.6, 0], order: 4 }));
  for (let i = 0; i < 5; i++) parts.push(mesh(new THREE.BoxGeometry(0.08, 0.5, 1.2), mat.steel(), { pos: [4.6 + i * 0.12, 1.6, 0] }));
  parts.push(decal(2.0, 0.8, canvasTex(256, 100, (g, w, h) => { g.fillStyle = '#16191d'; rr(g, 0, 0, w, h, 14); g.fill(); txt(g, '35 W', w / 2, h * 0.7, { size: 56, weight: 700, color: '#e6eef2', align: 'center' }); }), { pos: [0.8, 3.7, 1.46] }));
  return group(parts);
}

/* ── chest drainage unit (three graduated chambers) ── */
export function drainUnit() {
  const parts = [];
  const front = canvasTex(1024, 900, (g, w, h) => {
    g.fillStyle = '#f4f5f3'; g.fillRect(0, 0, w, h);
    const ch = [[0.05, 0.38, '#cfe6f6', 'COLLECTION'], [0.47, 0.22, '#2f7fd8', 'WATER SEAL'], [0.73, 0.22, '#e2a224', 'SUCTION']];
    ch.forEach(([x, cw, col, name], i) => {
      g.fillStyle = 'rgba(220,235,242,.9)'; rr(g, w * x, h * 0.12, w * cw, h * 0.7, 18); g.fill();
      g.strokeStyle = '#8fa3ad'; g.lineWidth = 4; g.stroke();
      if (i) { g.fillStyle = col; rr(g, w * x + 6, h * (i === 1 ? 0.55 : 0.48), w * cw - 12, h * (i === 1 ? 0.27 : 0.34) - 6, 12); g.fill(); }
      else { g.fillStyle = 'rgba(160,20,30,.75)'; rr(g, w * x + 6, h * 0.66, w * cw - 12, h * 0.16 - 6, 12); g.fill(); }
      for (let k = 0; k < 10; k++) g.fillRect(w * x + 8, h * 0.15 + k * h * 0.065, w * 0.05, 3);
      txt(g, name, w * (x + cw / 2), h * 0.9, { size: 30, weight: 700, color: '#2a3036', align: 'center' });
    });
    g.fillStyle = TEAL; g.fillRect(0, 0, w, h * 0.07);
    txt(g, 'CHEST DRAINAGE UNIT', w * 0.04, h * 0.052, { size: 40, weight: 800, color: '#fff' });
  });
  parts.push(mesh(rbox(16, 14, 5, 0.6, 4), [mat.plastic(0xeef0ef), mat.plastic(0xeef0ef), mat.plastic(0xeef0ef), mat.plastic(0xeef0ef), mat.printed(front), mat.plastic(0xeef0ef)], { pos: [0, 7, 0] }));
  // handle on top + floor stand
  parts.push(mesh(strap([V3(-5, 14, 0), V3(-4.5, 16, 0), V3(4.5, 16, 0), V3(5, 14, 0)], 2, 1.0, { up: V3(0, 0, 1), round: 0.9 }), mat.plastic(0x2a6fd0)));
  parts.push(mesh(rbox(18, 0.8, 8, 0.3, 2), mat.plastic(0x2a6fd0), { pos: [0, 0.4, 0] }));
  // tubes from the top
  parts.push(mesh(tube([V3(-4, 14, 1), V3(-4.5, 17, 1.5), V3(-7, 18.5, 3), V3(-10, 17, 4)], 0.45, { radial: 16 }), clearMat({ color: 0xeef6fa, roughness: 0.1, opacity: 0.35 }), { order: 4 }));
  return group(parts);
}

/* ── defibrillation pads (pair + lead + connector) ── */
export function defibPads() {
  const art = (flip) => canvasTex(512, 640, (g, w, h) => {
    g.fillStyle = '#f7f7f4'; rr(g, 0, 0, w, h, 60); g.fill();
    g.fillStyle = '#c62828'; rr(g, 0, 0, w, h * 0.12, 30); g.fill(); g.fillRect(0, h * 0.06, w, h * 0.06);
    txt(g, flip ? 'APEX' : 'STERNUM', w / 2, h * 0.09, { size: 44, weight: 800, color: '#fff', align: 'center' });
    // torso pictogram with the pad position
    g.strokeStyle = '#59636b'; g.lineWidth = 9; g.beginPath();
    g.moveTo(w * 0.3, h * 0.25); g.quadraticCurveTo(w * 0.5, h * 0.2, w * 0.7, h * 0.25); g.lineTo(w * 0.78, h * 0.8); g.lineTo(w * 0.22, h * 0.8); g.closePath(); g.stroke();
    g.beginPath(); g.arc(w * 0.5, h * 0.18, w * 0.07, 0, TAU); g.stroke();
    g.fillStyle = '#c62828'; rr(g, flip ? w * 0.55 : w * 0.3, flip ? h * 0.52 : h * 0.3, w * 0.16, h * 0.13, 8); g.fill();
    txt(g, 'ADULT', w / 2, h * 0.92, { size: 36, weight: 700, color: '#333', align: 'center' });
  });
  const parts = [];
  [[-4.2, 0.25, deg(-12), false], [4.2, -0.6, deg(10), true]].forEach(([x, z, ry, f]) => {
    const p = mesh(extrude(rrectShape(7.5, 9.5, 1.6), 0.35, { bevel: 0.12 }), [mat.printed(art(f), { roughness: 0.5 }), mat.matte(0xe8e8e3)]);
    p.rotation.set(-Math.PI / 2, 0, ry); p.position.set(x, 0.18, z);
    parts.push(p);
  });
  const lead = (x0, z0) => [V3(x0, 0.3, z0), V3(x0 * 0.6, 0.35, 6), V3(0.5, 0.35, 8.5), V3(1.5, 0.4, 10.5)];
  parts.push(mesh(tube(lead(-4.2, 4.4), 0.2, { radial: 10 }), mat.rubber(0xd8d9d6, { roughness: 0.5 })));
  parts.push(mesh(tube(lead(4.2, 4.0), 0.2, { radial: 10 }), mat.rubber(0xd8d9d6, { roughness: 0.5 })));
  parts.push(mesh(rbox(2.6, 1.3, 3.4, 0.4, 3), mat.plastic(0xc62828, { roughness: 0.4 }), { pos: [1.6, 0.65, 11.6], rot: [0, 0.3, 0] }));
  return group(parts);
}
