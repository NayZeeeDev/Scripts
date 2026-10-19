// Reusable product parts (vials, syringes, needles, rolls, bags, cases …) shared by the item and
// tool-belt models. Centimetres, +Y up, front = +Z.
import {
  THREE, V3, deg, mat, mesh, group, rbox, lathe, cyl, rcyl, tube, strap, pillow, extrude, rrectShape, wrapLabel, decal,
  canvasTex, txt, rr, NT, clearMat, merge, curve, helix, finePrint, barcode,
} from './lib.js';

const TAU = Math.PI * 2;

/* ───────────────────────────── glass vial (flip-off cap) ───────────────────────────── */
export function vial({ r = 1.15, h = 4.4, cap = 0xc8202a, capMetal = 0xc9ced3, liquid = 0x2e2c26, fill = 0.56, label = null, labelLen = TAU * 0.56, theta = 0, focus = 0.37, powder = false, amber = false, labelY0 = 0.1, labelY1 = 0.47 } = {}) {
  const body = h * 0.6, neckR = r * 0.42, neckY0 = h * 0.73, neckY1 = h * 0.78;
  const prof = [[0.001, 0.08], [r * 0.6, 0.02], [r - 0.12, 0], [r, 0.14], [r, body]];
  for (let i = 1; i <= 8; i++) { const t = i / 8, a = t * Math.PI / 2; prof.push([neckR + (r - neckR) * Math.cos(a), body + (neckY0 - body) * Math.sin(a)]); }
  prof.push([neckR, neckY1], [neckR * 1.32, neckY1 + h * 0.01], [neckR * 1.34, neckY1 + h * 0.07], [0.001, neckY1 + h * 0.07]);
  const glass = mesh(lathe(prof, { seg: 72 }), amber ? mat.glass({ color: 0xc8813a, opacity: 0.55, lum: 0.6 }) : mat.glass(), { order: 4 });
  const parts = [glass];
  // thick glass base (a bright ring that reads as glass)
  parts.push(mesh(lathe([[0.001, 0.02], [r - 0.14, 0.02], [r - 0.06, 0.12], [r - 0.08, 0.3], [0.001, 0.28]], { seg: 64 }), mat.glass({ opacity: 0.22 }), { order: 3 }));
  const inner = r - 0.08;
  if (powder) {
    parts.push(mesh(rcyl(inner, h * 0.16, 0.1, { y: 0.3 }), mat.matte(0xf4f1e8, { roughness: 0.95, normalMap: NT.plaster([2, 2]) })));
  } else if (fill > 0) {
    const ly = Math.min(body, h * fill);
    parts.push(mesh(lathe([[0.001, 0.3], [inner - 0.05, 0.3], [inner, 0.36], [inner, ly - 0.03], [inner - 0.06, ly], [0.001, ly]], { seg: 64 }), clearMat({ color: liquid, spec: 0xffffff, roughness: 0.05, opacity: 0.22, lum: 0.55, envMapIntensity: 1.2 }), { order: 2 }));
  }
  // grey rubber stopper visible under the crimp, aluminium crimp, plastic flip-off cap
  const cy0 = neckY1 - h * 0.005, ch = h * 0.09;
  parts.push(mesh(rcyl(neckR * 1.42, ch, 0.04, { y: cy0 }), mat.alu(capMetal, { roughness: 0.24, normalMap: NT.ribs([1, 4]), normalScale: new THREE.Vector2(0.12, 0.12) })));
  parts.push(mesh(rcyl(neckR * 1.46, h * 0.06, 0.08, { y: cy0 + ch - 0.02 }), mat.plastic(cap, { roughness: 0.32 })));
  if (label) parts.push(wrapLabel(r + 0.012, h * labelY0, h * labelY1, label, { theta, len: labelLen, focus }));
  return group(parts);
}

/* ───────────────────────────── glass ampoule ───────────────────────────── */
export function ampoule({ r = 0.62, h = 6.2, liquid = 0x2e2c26, ring = 0x7a3fc0, label = null, theta = 0, fill = 0.42 } = {}) {
  const prof = [[0.001, 0.04], [r * 0.8, 0], [r, 0.12], [r, h * 0.48], [r * 0.9, h * 0.53], [r * 0.42, h * 0.6], [r * 0.34, h * 0.63], [r * 0.48, h * 0.68], [r * 0.56, h * 0.76], [r * 0.5, h * 0.84], [r * 0.24, h * 0.95], [0.12, h * 0.99], [0.001, h]];
  const parts = [mesh(lathe(prof, { seg: 64 }), mat.glass({ opacity: 0.14 }), { order: 4 })];
  parts.push(mesh(lathe([[0.001, 0.08], [r - 0.08, 0.08], [r - 0.06, 0.15], [r - 0.06, h * fill], [0.001, h * fill]], { seg: 48 }), clearMat({ color: liquid, roughness: 0.05, opacity: 0.22, lum: 0.55, envMapIntensity: 1.2 }), { order: 2 }));
  // break ring at the neck
  parts.push(mesh(new THREE.TorusGeometry(r * 0.36, 0.05, 8, 48).rotateX(Math.PI / 2).translate(0, h * 0.62, 0), mat.plastic(ring, { roughness: 0.5 })));
  if (label) parts.push(wrapLabel(r + 0.008, h * 0.16, h * 0.4, label, { theta, len: TAU * 0.58, focus: 0.5 }));
  return group(parts);
}

// rotate a canvas texture by 90° (text that should run along a cylinder's axis)
export function rotTex(t, dir = 1) {
  const src = t.image, c = document.createElement('canvas');
  c.width = src.height; c.height = src.width;
  const g = c.getContext('2d');
  if (dir > 0) { g.translate(0, c.height); g.rotate(-Math.PI / 2); } else { g.translate(c.width, 0); g.rotate(Math.PI / 2); }
  g.drawImage(src, 0, 0);
  const n = new THREE.CanvasTexture(c); n.colorSpace = t.colorSpace; n.anisotropy = 8;
  return n;
}

/* ───────────────────────────── syringe (axis = +X, tip at +X) ───────────────────────────── */
// gradTex: printed scale (alpha); returns group lying along X centred on the barrel
export function gradTex(ml = 10, { color = '#1b1f24' } = {}) {
  return canvasTex(1024, 256, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.fillStyle = color;
    const n = ml * 5, x0 = w * 0.08, x1 = w * 0.92;
    for (let i = 0; i <= n; i++) {
      const x = x0 + (x1 - x0) * (i / n), major = i % 5 === 0;
      g.fillRect(x - 1.5, h * 0.5, 3, major ? h * 0.32 : h * 0.18);
      if (major && i) txt(g, String(i / 5), x, h * 0.42, { size: 44, weight: 600, color, align: 'center', font: '"Inter", sans-serif' });
    }
  });
}
export function syringe({ len = 7.5, r = 0.72, ml = 10, fill = 0.7, liquid = 0xeef5fa, plunger = 0xf4f5f6, stopper = 0x2c2f33, needle = null, cap = null, label = null, labelDir = 1, labelTheta = -Math.PI / 4, grad = true, tip = 'luer' } = {}) {
  const parts = [];
  const x0 = -len / 2, x1 = len / 2;
  // barrel (lathe along Y, then rotated to X)
  const bp = [[r * 0.98, 0], [r, 0.05], [r, len], [r * 0.96, len + 0.06], [r * 0.45, len + 0.28], [r * 0.32, len + 0.34], [r * 0.3, len + 0.9], [r * 0.24, len + 0.95], [0.001, len + 0.95]];
  const barrel = mesh(lathe(bp, { seg: 64 }), mat.glass({ color: 0x4e575c, opacity: 0.1, roughness: 0.07 }), { order: 4 });
  barrel.rotation.z = -Math.PI / 2; barrel.position.x = x0;
  parts.push(barrel);
  // finger flange
  const fl = mesh(extrude(rrectShape(r * 2.1, r * 4.2, r * 0.9), 0.16, { bevel: 0.05 }), mat.glass({ color: 0x4e575c, opacity: 0.28 }), { order: 4 });
  fl.rotation.y = Math.PI / 2; fl.position.x = x0 + 0.02;
  parts.push(fl);
  // stopper + liquid
  const sx = x0 + 0.25 + (1 - fill) * (len - 0.6);
  const st = mesh(lathe([[0.001, 0], [r * 0.9, 0], [r * 0.96, 0.08], [r * 0.96, 0.18], [r * 0.86, 0.24], [r * 0.96, 0.32], [r * 0.96, 0.42], [r * 0.7, 0.55], [0.001, 0.6]], { seg: 48 }), mat.rubber(stopper, { roughness: 0.45 }));
  st.rotation.z = -Math.PI / 2; st.position.x = sx;
  parts.push(st);
  if (fill > 0.02) {
    const ll = x1 - (sx + 0.6);
    const lq = mesh(cyl(r * 0.92, ll, { seg: 48 }), mat.liquid(liquid, { opacity: 0.35 }), { order: 2 });
    lq.rotation.z = -Math.PI / 2; lq.position.x = sx + 0.6;
    parts.push(lq);
  }
  // plunger rod (cross section) + thumb press
  const rodLen = sx - x0 + 2.2;
  const rodMat = mat.plastic(plunger, { roughness: 0.45 });
  const rodA = mesh(new THREE.BoxGeometry(rodLen, r * 1.55, 0.12), rodMat), rodB = mesh(new THREE.BoxGeometry(rodLen, 0.12, r * 1.55), rodMat);
  rodA.position.x = rodB.position.x = sx - rodLen / 2;
  parts.push(rodA, rodB);
  const thumb = mesh(rcyl(r * 1.15, 0.16, 0.06), rodMat);
  thumb.rotation.z = -Math.PI / 2; thumb.position.x = sx - rodLen;
  parts.push(thumb);
  if (grad) {
    const gm = new THREE.MeshBasicMaterial({ map: gradTex(ml), transparent: true, depthWrite: false, toneMapped: false, color: 0x222222 });
    const gl = mesh(new THREE.CylinderGeometry(r + 0.012, r + 0.012, len * 0.86, 48, 1, true, -Math.PI * 0.35, Math.PI * 0.7), gm, { order: 5 });
    gl.rotation.z = -Math.PI / 2; gl.rotation.x = -Math.PI * 0.08; gl.position.x = x0 + len * 0.5;
    gl.userData.noShadow = true;
    parts.push(gl);
  }
  if (label) {
    // label canvas is landscape (text along the barrel): rotate it so it runs along the axis
    const lb = wrapLabel(r + 0.015, 0, len * 0.62, rotTex(label, labelDir), { len: TAU * 0.5, theta: labelTheta });
    lb.rotation.z = -Math.PI / 2; lb.position.x = x0 + len * 0.2;
    parts.push(lb);
  }
  const tipX = x1 + 0.95;
  if (needle) parts.push(hypoNeedle({ ...needle, x: tipX - 0.55 }));
  else if (cap) {
    const c = mesh(rcyl(r * 0.42, 0.9, 0.08), mat.plastic(cap, { roughness: 0.4 }));
    c.rotation.z = -Math.PI / 2; c.position.x = x1 + 0.3;
    parts.push(c);
  }
  return group(parts);
}

/* ───────────────────────────── hypodermic needle (axis X, hub at x) ───────────────────────────── */
export function hypoNeedle({ x = 0, len = 3.8, hub = 0xe8cf2e, gauge = 0.045, capped = false, capColor = hub, hubLen = 1.25 } = {}) {
  const parts = [];
  const hp = [[0.3, 0], [0.33, 0.05], [0.33, 0.25], [0.29, 0.3], [0.26, hubLen * 0.75], [0.16, hubLen * 0.95], [0.1, hubLen], [0.001, hubLen]];
  const h = mesh(lathe(hp, { seg: 40 }), clearMat({ color: hub, roughness: 0.25, opacity: 0.8, lum: 0.6, side: THREE.FrontSide }), { order: 3 });
  h.rotation.z = -Math.PI / 2; h.position.x = x;
  parts.push(h);
  // luer wings
  const wing = mesh(new THREE.BoxGeometry(0.22, 0.08, 0.86), mat.plastic(hub, { roughness: 0.35 }));
  wing.position.x = x + 0.12;
  parts.push(wing);
  if (capped) {
    const c = mesh(lathe([[0.28, 0], [0.24, 0.3], [0.2, len * 0.9], [0.14, len], [0.001, len + 0.02]], { seg: 32 }), mat.plastic(capColor, { roughness: 0.4, transparent: true, opacity: 0.85 }));
    c.rotation.z = -Math.PI / 2; c.position.x = x + hubLen - 0.1;
    parts.push(c);
  } else {
    const n = mesh(cyl(gauge, len, { seg: 16 }), mat.steel({ roughness: 0.12 }));
    n.rotation.z = -Math.PI / 2; n.position.x = x + hubLen - 0.05;
    // bevel tip
    const tip = mesh(new THREE.ConeGeometry(gauge, 0.22, 16).rotateZ(-Math.PI / 2), mat.steel({ roughness: 0.1 }));
    tip.position.x = x + hubLen - 0.05 + len + 0.1;
    parts.push(n, tip);
  }
  return group(parts);
}

/* ───────────────────────────── roll (bandage / gauze / plaster) ───────────────────────────── */
export function rollEnd(color = '#efe6d6', { rings = 26, core = 0.22, coreColor = '#cbbfa8', line = 'rgba(0,0,0,.13)' } = {}) {
  return canvasTex(512, 512, (g, w) => {
    g.fillStyle = color; g.beginPath(); g.arc(w / 2, w / 2, w / 2, 0, TAU); g.fill();
    g.strokeStyle = line; g.lineWidth = 2;
    for (let i = 0; i < rings; i++) { const rr_ = w / 2 * (core + (1 - core) * (i / rings)) + Math.sin(i * 7.1) * 1.5; g.beginPath(); g.arc(w / 2 + Math.sin(i) * 1.2, w / 2, rr_, 0, TAU); g.stroke(); }
    g.fillStyle = coreColor; g.beginPath(); g.arc(w / 2, w / 2, w / 2 * core, 0, TAU); g.fill();
    g.fillStyle = 'rgba(0,0,0,.25)'; g.beginPath(); g.arc(w / 2, w / 2, w / 2 * core * 0.8, 0, TAU); g.fill();
  });
}
// roll lying on its side (axis = Z); tail = flat strip unrolling towards +X
export function roll({ r = 2.4, w = 5, color = 0xeadfcb, end = null, normal = 'crepe', tail = 6, tailColor = null, rough = 0.95, core = 0.28, stripe = null } = {}) {
  const parts = [];
  const nm = normal ? NT[normal](normal === 'crepe' ? [10, 1] : [6, 3]) : null;
  const sideMat = mat.matte(color, { roughness: rough, normalMap: nm, normalScale: new THREE.Vector2(0.7, 0.7) });
  if (stripe) sideMat.map = stripe;
  const side = mesh(new THREE.CylinderGeometry(r, r, w, 96, 1, true), sideMat);
  side.rotation.x = Math.PI / 2; side.position.y = r;
  parts.push(side);
  const endMat = mat.matte(0xffffff, { map: end || rollEnd('#' + new THREE.Color(color).getHexString(), { core }), roughness: 0.95 });
  for (const s of [1, -1]) {
    const e = mesh(new THREE.CircleGeometry(r, 96), endMat);
    e.position.set(0, r, s * w / 2); if (s < 0) e.rotation.y = Math.PI;
    parts.push(e);
  }
  if (tail) {
    // strip leaves the roll at the bottom front and lies flat on the floor
    const t = 0.09;
    const pts = [V3(-r * 0.15, r * 0.02 + t, 0), V3(r * 0.35, t / 2 + 0.01, 0), V3(r * 0.35 + tail * 0.5, t / 2, 0), V3(r * 0.35 + tail, t / 2 + 0.02, 0)];
    const s = mesh(strap(pts, w * 0.995, t, { up: V3(0, 0, 1), round: 0.5 }), mat.matte(tailColor ?? color, { roughness: rough, normalMap: nm, normalScale: new THREE.Vector2(0.7, 0.7) }));
    parts.push(s);
  }
  return group(parts);
}

/* ───────────────────────────── hard case (kit) ───────────────────────────── */
export function hardCase({ w = 30, h = 10, d = 22, color = 0xc81e2c, trim = 0x2a2d31, latch = 0xdfe3e7, front = null, top = null, handle = 0x1f2226, lidLine = 0.62 } = {}) {
  const parts = [];
  const body = mat.plastic(color, { roughness: 0.42, clearcoat: 0.35, normalMap: NT.grain([3, 3]), normalScale: new THREE.Vector2(0.25, 0.25) });
  const base = mesh(rbox(w, h * lidLine, d, 1.2, 5), body); base.position.y = h * lidLine / 2;
  const lid = mesh(rbox(w, h * (1 - lidLine) + 0.6, d, 1.2, 5), body); lid.position.y = h - (h * (1 - lidLine) + 0.6) / 2;
  parts.push(base, lid);
  // seam groove + rubber gasket line
  const seam = mesh(rbox(w - 0.1, 0.22, d - 0.1, 0.1, 2), mat.matte(trim, { roughness: 0.7 })); seam.position.y = h * lidLine + 0.05; seam.scale.set(1.004, 1, 1.006);
  parts.push(seam);
  // latches on the front
  for (const s of [-1, 1]) {
    const l = mesh(rbox(3.2, 3.4, 0.9, 0.35, 3), mat.plastic(latch, { roughness: 0.3 }));
    l.position.set(s * w * 0.3, h * lidLine + 0.3, d / 2 + 0.25);
    parts.push(l);
  }
  // carry handle on the front edge of the lid (top view) — folded flat
  const hp = [V3(-w * 0.17, h + 0.05, d * 0.18), V3(-w * 0.15, h + 1.1, d * 0.2), V3(0, h + 1.5, d * 0.21), V3(w * 0.15, h + 1.1, d * 0.2), V3(w * 0.17, h + 0.05, d * 0.18)];
  parts.push(mesh(strap(hp, 1.6, 1.0, { up: V3(0, 0, 1), round: 0.9 }), mat.rubber(handle, { roughness: 0.6 })));
  for (const s of [-1, 1]) { const b = mesh(rbox(2.2, 0.9, 2.4, 0.4, 3), mat.plastic(handle, { roughness: 0.5 })); b.position.set(s * w * 0.17, h + 0.3, d * 0.18); parts.push(b); }
  if (front) parts.push(decal(w * 0.42, w * 0.42 * 0.36, front, { pos: [0, h * 0.32, d / 2 + 0.02] }));
  if (top) parts.push(decal(w * 0.5, d * 0.5, top, { pos: [0, h + 0.02, -d * 0.12], rot: [-Math.PI / 2, 0, 0] }));
  return group(parts);
}

/* ───────────────────────────── soft medical bag (IV / blood) ───────────────────────────── */
// bag hangs in the XY plane (front +Z); returns group, bottom ports at y = 0
export function fluidBag({ w = 9, h = 15, t = 2.2, fill = 0.85, liquid = 0xeef4f8, liquidOpacity = 0.25, label = null, labelW = 0.72, labelH = 0.5, labelY = 0.55, ports = 2, portColors = [0x2f7fd8, 0xffffff], filmColor = 0xf3f8fb, hanger = true } = {}) {
  const parts = [];
  const [f, b] = pillow(w, h, t, { seam: 0.55, nx: 48, ny: 72, power: 0.55, ramp: 2.0 });
  const film = mat.film({ color: filmColor, opacity: 0.22 });
  const fm = mesh(f, film, { order: 4 }), bm = mesh(b, film, { order: 4 });
  const by = 1.6 + h / 2;
  fm.position.y = bm.position.y = by;
  parts.push(fm, bm);
  if (fill > 0) {
    const [lf, lb] = pillow(w - 0.9, h * fill - 0.6, t * 0.92, { seam: 0.2, nx: 40, ny: 60, power: 0.55, ramp: 2.2 });
    const lm = mat.liquid(liquid, { opacity: liquidOpacity, lum: 0.3 });
    const a = mesh(lf, lm, { order: 2 }), c = mesh(lb, lm, { order: 2 });
    a.position.y = c.position.y = 1.6 + 0.3 + (h * fill - 0.6) / 2 + 0.05;
    parts.push(a, c);
  }
  if (label) {
    // label printed on the film, following the bulge
    const [lf] = pillow(w * labelW, h * labelH, t * 0.98, { seam: 0.01, nx: 32, ny: 32, power: 0.55, ramp: 4, shape: (x, y) => {
      const X = x / (w / 2 - 0.55), Y = (y + h * (labelY - 0.5)) / (h / 2 - 0.55);
      return Math.pow(Math.min(1, (1 - Math.abs(X)) * 2.0) * Math.min(1, (1 - Math.abs(Y)) * 2.0), 0.55);
    } });
    const lm = mesh(lf, new THREE.MeshPhysicalMaterial({ map: label, roughness: 0.4, clearcoat: 0.5, transparent: true, alphaTest: 0.05, polygonOffset: true, polygonOffsetFactor: -2 }), { order: 5 });
    lm.position.set(0, by + h * (labelY - 0.5), 0.02);
    lm.castShadow = false;
    parts.push(lm);
  }
  // ports at the bottom
  const px = ports === 1 ? [0] : ports === 2 ? [-w * 0.18, w * 0.18] : [-w * 0.26, 0, w * 0.26];
  px.forEach((x, i) => {
    const pc = portColors[i % portColors.length];
    parts.push(mesh(cyl(0.32, 1.9, { y: 0.0 }), mat.glass({ opacity: 0.45 }), { pos: [x, 0, 0], order: 4 }));
    parts.push(mesh(rcyl(0.42, 0.75, 0.12, { y: 0 }), mat.plastic(pc, { roughness: 0.35 }), { pos: [x, -0.2, 0] }));
  });
  if (hanger) {
    const s = rrectShape(2.6, 1.6, 0.5); s.holes.push(new THREE.Path().absellipse(0, 0, 0.8, 0.35, 0, TAU, true));
    const hm = mesh(extrude(s, 0.08, { bevel: 0.02 }), film, { order: 4 });
    hm.position.set(0, by + h / 2 + 0.6, 0);
    parts.push(hm);
  }
  return group(parts);
}

export { TAU };

/* ═════════════════════════════ steel instruments (lying flat, axis = +X, tip at +X) ═════════════════════════════ */
// arm of a ringed instrument: ring at the back, shank to the pivot, jaw to the tip
function ringArm({ side = 1, len = 14, ringR = 0.95, open = 0.0, jawLen = 3.2, curve = 0.0, width = 0.42, thick = 0.32, m }) {
  const parts = [];
  const pivot = len * 0.42;
  // ring centre sits beside the axis
  const rc = V3(-len * 0.5 + ringR, 0, side * (ringR * 1.15 + open));
  const ring = mesh(new THREE.TorusGeometry(ringR, 0.17, 14, 48).rotateX(Math.PI / 2), m);
  ring.position.copy(rc).setY(thick / 2);
  parts.push(ring);
  // shank from the ring to the pivot (crossing to the other side), jaw onwards
  const p0 = V3(rc.x + ringR * 0.85, thick / 2, rc.z - side * ringR * 0.45);
  const pv = V3(-len * 0.5 + pivot, thick / 2, 0);
  const pts = [p0, V3(p0.x + (pv.x - p0.x) * 0.5, thick / 2, side * (0.32 + open * 0.5)), pv,
    V3(pv.x + jawLen * 0.5, thick / 2, -side * 0.06 + curve * 0.25), V3(pv.x + jawLen, thick / 2, -side * 0.02 + curve)];
  const cv = new THREE.CatmullRomCurve3(pts, false, 'catmullrom', 0.4);
  parts.push(mesh(strap(cv, thick, width, { up: V3(0, 1, 0), round: 0.8, steps: 160 }), m));
  return parts;
}
export function hemostat({ len = 14, curved = true, open = 0.25, gold = false, jaw = 3.4 } = {}) {
  const m = mat.steel({ roughness: 0.22 });
  const parts = [...ringArm({ side: 1, len, open, jawLen: jaw, curve: curved ? 0.9 : 0, m }), ...ringArm({ side: -1, len, open, jawLen: jaw, curve: curved ? 0.9 : 0, m })];
  if (gold) parts.filter(p => p.geometry.type === 'TorusGeometry').forEach(p => { p.material = mat.gold(); });
  // box lock + screw
  const pivotX = -len * 0.5 + len * 0.42;
  parts.push(mesh(rbox(0.9, 0.42, 0.62, 0.12, 2), m, { pos: [pivotX, 0.21, 0] }));
  parts.push(mesh(cyl(0.16, 0.05, { y: 0.42 }), mat.steel({ roughness: 0.4 }), { pos: [pivotX, 0, 0] }));
  // ratchets near the rings
  for (const s of [1, -1]) for (let i = 0; i < 4; i++) parts.push(mesh(new THREE.BoxGeometry(0.1, 0.18, 0.28), m, { pos: [-len * 0.5 + 2.6 + i * 0.16, 0.2, s * (0.33 + open * 0.4)] }));
  return group(parts);
}
export function scalpel({ len = 14, blade = true } = {}) {
  const parts = [];
  // flat handle with a knurled grip, then the blade
  const hs = new THREE.Shape();
  hs.moveTo(-len / 2, -0.45); hs.lineTo(len / 2 - 2.2, -0.42); hs.lineTo(len / 2 - 0.9, -0.22); hs.lineTo(len / 2, -0.2); hs.lineTo(len / 2, 0.2); hs.lineTo(len / 2 - 0.9, 0.22); hs.lineTo(len / 2 - 2.2, 0.42); hs.lineTo(-len / 2, 0.45); hs.lineTo(-len / 2, -0.45);
  const handle = mesh(extrude(hs, 0.26, { bevel: 0.06 }), mat.satin());
  handle.rotation.x = -Math.PI / 2; handle.position.y = 0.13;
  parts.push(handle);
  const grip = mesh(rbox(len * 0.38, 0.06, 0.74, 0.03, 1), mat.steel({ color: 0x8d949b, roughness: 0.55, normalMap: NT.knurl([10, 2]), normalScale: new THREE.Vector2(1, 1) }));
  grip.position.set(-len * 0.12, 0.265, 0);
  parts.push(grip);
  if (blade) {
    const bs = new THREE.Shape();
    bs.moveTo(0, -0.22); bs.lineTo(1.2, -0.28); bs.bezierCurveTo(2.6, -0.42, 3.6, -0.15, 4.2, 0.18); bs.lineTo(3.0, 0.18); bs.lineTo(0, 0.24); bs.lineTo(0, -0.22);
    const b = mesh(extrude(bs, 0.05, { bevel: 0.012, bevelSeg: 1 }), mat.chrome({ roughness: 0.1 }));
    b.rotation.x = -Math.PI / 2; b.position.set(len / 2 - 0.5, 0.13, 0); b.scale.set(1.5, 2.3, 1);
    parts.push(b);
  }
  return group(parts);
}
export function thumbForceps({ len = 13, spread = 0.9 } = {}) {
  const m = mat.steel({ roughness: 0.24 });
  const parts = [];
  for (const s of [1, -1]) {
    const pts = [V3(-len / 2, 0.45, 0), V3(-len / 2 + 1.2, 0.45, s * 0.18), V3(0, 0.45, s * spread * 0.55), V3(len / 2 - 2, 0.45, s * spread * 0.32), V3(len / 2, 0.45, s * 0.04)];
    parts.push(mesh(strap(pts, 0.9, 0.14, { up: V3(0, 1, 0), round: 0.6 }), m));
    // grip serrations
    const gr = mesh(rbox(3.2, 0.62, 0.02, 0.01, 1), mat.steel({ roughness: 0.5, normalMap: NT.ribs([12, 1]) }));
    gr.position.set(-0.6, 0.45, s * (spread * 0.53 + 0.08)); gr.rotation.y = s * 0.02;
    parts.push(gr);
  }
  return group(parts);
}
export function scissors({ len = 14, open = 0.18, curved = false } = {}) {
  const m = mat.steel({ roughness: 0.2 });
  const parts = [];
  for (const s of [1, -1]) {
    const g = group([], {});
    const ringR = 0.95;
    const ring = mesh(new THREE.TorusGeometry(ringR, 0.18, 14, 48).rotateX(Math.PI / 2), m, { pos: [-len / 2 + ringR, 0.18 + (s > 0 ? 0.3 : 0), s * 1.25] });
    const sh = [V3(-len / 2 + ringR * 1.8, 0.18 + (s > 0 ? 0.3 : 0), s * 0.95), V3(-len * 0.12, 0.18 + (s > 0 ? 0.3 : 0), s * 0.32), V3(-0.4, 0.18 + (s > 0 ? 0.3 : 0), 0)];
    g.add(ring, mesh(strap(sh, 0.32, 0.42, { up: V3(0, 1, 0), round: 0.8 }), m));
    // blade
    const bs = new THREE.Shape();
    bs.moveTo(-0.6, 0); bs.lineTo(len * 0.48, s * -0.02); bs.quadraticCurveTo(len * 0.5, s * 0.12, len * 0.47, s * 0.28); bs.lineTo(0.2, s * 0.62); bs.lineTo(-0.6, s * 0.45); bs.lineTo(-0.6, 0);
    const bl = mesh(extrude(bs, 0.22, { bevel: 0.05 }), m);
    bl.rotation.x = -Math.PI / 2; bl.position.y = 0.18 + (s > 0 ? 0.3 : 0);
    g.add(bl);
    g.rotation.y = s * open * 0.5;
    parts.push(g);
  }
  parts.push(mesh(cyl(0.22, 0.75, { y: 0 }), mat.steel({ roughness: 0.35 })));
  return group(parts);
}
// curved suture needle with thread (lying flat), centre at origin
export function sutureNeedle({ r = 1.1, thread = 0x1d2733, threadLen = 1, arc = Math.PI * 0.9 } = {}) {
  const pts = [];
  for (let i = 0; i <= 40; i++) { const a = -arc / 2 + (i / 40) * arc; pts.push(V3(Math.sin(a) * r, 0.06, -Math.cos(a) * r)); }
  const parts = [mesh(tube(pts, 0.05, { radial: 10, tubular: 60 }), mat.steel({ roughness: 0.12 }))];
  parts.push(mesh(new THREE.ConeGeometry(0.05, 0.2, 10).rotateZ(-Math.PI / 2).rotateY(-arc / 2 + Math.PI / 2), mat.steel(), { pos: [pts[40].x, 0.06, pts[40].z] }));
  if (threadLen) {
    const t0 = pts[0], tp = [t0];
    for (let i = 1; i <= 30; i++) { const k = i / 30; tp.push(V3(t0.x - k * 4 * threadLen + Math.sin(k * 7) * 0.6, 0.04, t0.z + Math.sin(k * 4.2) * 1.4 * threadLen + k * 1.2)); }
    parts.push(mesh(tube(tp, 0.035, { radial: 8 }), mat.matte(thread, { roughness: 0.6 })));
  }
  return group(parts);
}

/* ═════════════════════════════ packaging ═════════════════════════════ */
// sealed sachet lying on the floor: printed front (tex), crimped seam; foil = metallic base
export function sachet({ w = 10, h = 12, t = 0.7, tex, back = 0xdcdcdc, foil = false, seam = 0.8, rough = 0.45 } = {}) {
  const [f, b] = pillow(w, h, t, { seam, nx: 48, ny: 48, power: 0.4, ramp: 2.6 });
  const fm = foil ? new THREE.MeshPhysicalMaterial({ map: tex, metalness: 0.55, roughness: 0.32, clearcoat: 0.6, normalMap: NT.crinkle([2, 2]), normalScale: new THREE.Vector2(0.12, 0.12) })
    : new THREE.MeshPhysicalMaterial({ map: tex, roughness: rough, clearcoat: 0.3, clearcoatRoughness: 0.4 });
  const bm = foil ? mat.alu(back, { roughness: 0.35 }) : mat.matte(back);
  const g = group([mesh(f, fm), mesh(b, bm)]);
  g.rotation.x = -Math.PI / 2; g.position.y = t / 2;
  return group([g]);
}
// peel pouch: paper back + clear film front; `contents` sit on the paper (y ≥ 0 at paper top)
export function peelPouch({ w = 12, h = 22, paper, contents = null, bulge = 0.9 } = {}) {
  const parts = [];
  const back = mesh(rbox(w, 0.06, h, 0.02, 1), [mat.matte(0xf2f1ea), mat.matte(0xf2f1ea), mat.paper(paper, { roughness: 0.85 }), mat.matte(0xe9e8e0), mat.matte(0xf2f1ea), mat.matte(0xf2f1ea)]);
  back.position.y = 0.03;
  parts.push(back);
  const [f] = pillow(w, h, bulge * 2, { seam: 0.9, nx: 40, ny: 60, power: 0.45, ramp: 2.2 });
  const film = mesh(f, clearMat({ color: 0xf4f9fb, roughness: 0.12, opacity: 0.06, lum: 0.3 }), { order: 6 });
  film.rotation.x = -Math.PI / 2; film.position.y = 0.065;
  film.userData.noShadow = true;
  parts.push(film);
  if (contents) { contents.position.y += 0.07; parts.push(contents); }
  return group(parts);
}
// coiled tubing lying on the floor
export function tubingCoil({ r = 3, turns = 2.4, tubeR = 0.22, color = 0xf3f8fb, clear = true, x = 0, z = 0, lead = null, wobble = 0.35, seed = 1 } = {}) {
  const pts = [];
  const N = Math.ceil(turns * 40);
  for (let i = 0; i <= N; i++) {
    const a = (i / N) * turns * TAU, rr_ = r * (1 + Math.sin(a * 1.7 + seed) * 0.06 * wobble * 3);
    pts.push(V3(x + Math.cos(a) * rr_, tubeR + (i / N) * tubeR * 2.2 + Math.max(0, Math.sin(a * 2 + seed)) * tubeR * 0.6, z + Math.sin(a) * rr_ * 0.92));
  }
  if (lead) lead.forEach(p => pts.push(Array.isArray(p) ? V3(...p) : p));
  const m = clear ? clearMat({ color, roughness: 0.1, opacity: 0.35, lum: 0.75 }) : mat.plastic(color, { roughness: 0.4 });
  return mesh(tube(pts, tubeR, { radial: 14 }), m, { order: clear ? 4 : 0 });
}
export function tablet({ r = 0.55, t = 0.3, color = 0xf7f6f1, score = true } = {}) {
  const g = lathe([[0.001, 0], [r * 0.8, 0.0], [r, t * 0.3], [r, t * 0.7], [r * 0.8, t], [0.001, t + t * 0.12]], { seg: 40, smooth: 30 });
  const parts = [mesh(g, mat.matte(color, { roughness: 0.65 }))];
  if (score) parts.push(mesh(new THREE.BoxGeometry(r * 1.7, 0.05, 0.06), mat.matte(0xd8d6cf), { pos: [0, t + 0.02, 0] }));
  return group(parts);
}

/* ═════════════════════════════ IV cannula (axis +X, tip +X) ═════════════════════════════ */
export const GAUGE = { 14: 0xe8742a, 16: 0x8c8f93, 18: 0x2fa64a, 20: 0xe2668f, 22: 0x2f7fd8, 24: 0xf2d43b };
export function ivCannula({ gauge = 18, len = 4.6, capOn = false } = {}) {
  const col = GAUGE[gauge] || 0xe2668f;
  const parts = [];
  // catheter hub with wings + injection port
  const hub = mesh(lathe([[0.36, 0], [0.4, 0.1], [0.4, 0.9], [0.3, 1.5], [0.2, 1.9], [0.12, 2.0], [0.001, 2.0]], { seg: 40 }), mat.plastic(col, { roughness: 0.3 }));
  hub.rotation.z = -Math.PI / 2; hub.position.x = -1.5;
  parts.push(hub);
  const wing = new THREE.Shape(); wing.moveTo(-0.6, 0); wing.quadraticCurveTo(-0.7, 1.4, 0, 1.6); wing.quadraticCurveTo(0.7, 1.4, 0.6, 0); wing.lineTo(-0.6, 0);
  for (const s of [1, -1]) { const w = mesh(extrude(wing, 0.09, { bevel: 0.03 }), mat.plastic(col, { roughness: 0.35 })); w.rotation.x = -Math.PI / 2; w.rotation.z = s > 0 ? 0 : Math.PI; w.position.set(-0.8, 0.0, s * 0.3); w.scale.set(1, s, 1); parts.push(w); }
  const port = mesh(rcyl(0.26, 0.75, 0.08), mat.plastic(col, { roughness: 0.3 }));
  port.position.set(-1.0, 0.25, 0);
  parts.push(port);
  parts.push(mesh(rcyl(0.33, 0.2, 0.06), mat.plastic(0xffffff), { pos: [-1.0, 0.95, 0] }));
  // catheter + needle
  const cat = mesh(cyl(0.07, len, { seg: 20 }), clearMat({ color: 0xf6fbff, roughness: 0.15, opacity: 0.4 }), { order: 3 });
  cat.rotation.z = -Math.PI / 2; cat.position.x = 0.45;
  parts.push(cat);
  const nd = mesh(cyl(0.045, len + 0.4, { seg: 14 }), mat.steel({ roughness: 0.1 }));
  nd.rotation.z = -Math.PI / 2; nd.position.x = 0.4;
  parts.push(nd);
  // needle grip with flash chamber at the back
  const grip = mesh(lathe([[0.001, 0], [0.35, 0], [0.42, 0.2], [0.42, 2.6], [0.36, 2.8], [0.001, 2.85]], { seg: 32 }), clearMat({ color: 0xf2f7fa, roughness: 0.15, opacity: 0.35, lum: 0.7, side: THREE.FrontSide }), { order: 3 });
  grip.rotation.z = Math.PI / 2; grip.position.x = -1.5;
  parts.push(grip);
  parts.push(mesh(cyl(0.2, 1.2, { seg: 20 }), mat.plastic(0xffffff, { roughness: 0.4 }), { pos: [-3.9, 0, 0], rot: [0, 0, -Math.PI / 2] }));
  parts.push(mesh(rcyl(0.32, 0.5, 0.1), mat.plastic(col, { roughness: 0.35 }), { pos: [-4.5, 0, 0], rot: [0, 0, -Math.PI / 2] }));
  const g = group(parts);
  g.position.y = 0.42;
  return group([g]);
}

/* ═════════════════════════════ printed flat things ═════════════════════════════ */
export function card({ w = 8.56, h = 5.4, t = 0.08, front, back = null, r = 0.32 } = {}) {
  const geo = extrude(rrectShape(w, h, r), t, { bevel: 0.015, bevelSeg: 1 });
  const m = new THREE.MeshPhysicalMaterial({ map: front, roughness: 0.3, clearcoat: 0.8, clearcoatRoughness: 0.15 });
  const c = mesh(geo, m);
  c.rotation.x = -Math.PI / 2; c.position.y = t / 2;
  return group([c]);
}
