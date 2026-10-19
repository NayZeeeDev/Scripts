// Tool-belt models for the minigame HUD (NZA.ui.ProcPanel): one entry per tl.icon name that
// stands for a physical tool (html/apps/*/ tools lists). Rendered at 256 px (html/img/tools).
// Icon names that are UI glyphs (check, x, arrows, hand, target, …) are deliberately absent.
import {
  THREE, V3, deg, mat, mesh, group, rbox, lathe, cyl, rcyl, tube, strap, pillow, extrude, rrectShape, wrapLabel, decal,
  canvasTex, txt, rr, NT, clearMat, finePrint, barcode, helix, bend, rng,
} from '../lib.js';
import { syringe, hypoNeedle, ivCannula, hemostat, scalpel, thumbForceps, scissors, sutureNeedle, tubingCoil, TAU } from '../parts.js';
import { drugLabel } from '../labels.js';
import {
  TEAL, bandageRoll, gauzeStack, gauzeRoll, islandDressing, salineBottle, contrastBottle, salineBag, bloodBag, foilBlanket, xrayFilm,
  emboCoil, ett, yankauer, dermatome, mesher, skinStapler, drainUnit, defibPads,
} from './common.js';

const V = (az = 30, elev = 30, extra = {}) => ({ az, elev, fill: 0.86, ...extra });
const yaw = (o, d) => { o.rotation.y = deg(d); return o; };
const at = (o, x, y, z) => { o.position.set(x, y, z); return o; };
const TQ_TEAL = 0x34b8a8;

/* ── tourniquet windlass rod with the strap twisted round it ── */
function windlass({ strapOn = true } = {}) {
  const parts = [];
  const rod = mat.plastic(TQ_TEAL, { roughness: 0.4 });
  parts.push(mesh(rcyl(0.6, 13, 0.25), rod, { pos: [-6.5, 0.6, 0], rot: [0, 0, -Math.PI / 2] }));
  for (const s of [-1, 1]) parts.push(mesh(new THREE.CylinderGeometry(0.64, 0.64, 2.6, 32, 1, true).rotateZ(Math.PI / 2), mat.plastic(TQ_TEAL, { roughness: 0.6, normalMap: NT.knurl([3, 3]), normalScale: new THREE.Vector2(0.8, 0.8) }), { pos: [s * 4.8, 0.6, 0] }));
  if (strapOn) {
    const pts = [V3(0, 0.07, -8), V3(0, 0.07, -4)];
    for (let i = 0; i <= 40; i++) { const a = -Math.PI / 2 + i / 40 * TAU * 1.25; pts.push(V3(0.15 * i / 40, 0.6 + Math.sin(a) * 0.82, -Math.cos(a) * 0.82 * -1)); }
    pts.push(V3(0.2, 0.07, 3.8), V3(0.2, 0.07, 8));
    const web = mat.fabric(0x1e2124, { normalMap: NT.weave([1, 1]), normalScale: new THREE.Vector2(0.8, 0.8) });
    parts.push(mesh(strap(pts, 3.6, 0.16, { up: V3(1, 0, 0), tension: 0.3, steps: 260 }), web));
  }
  return group(parts);
}
/* ── windlass clip (triangular keeper) with the rod snapped in + time strap ── */
function tqClip() {
  const black = mat.plastic(0x1d2023, { roughness: 0.55 });
  const parts = [];
  parts.push(mesh(rbox(7.5, 0.6, 4.2, 0.25, 3), black, { pos: [0, 0.3, 0] }));
  for (const s of [-1, 1]) {
    const c = new THREE.Shape();
    c.moveTo(-0.4, 0); c.lineTo(0.4, 0); c.lineTo(0.4, 2.2); c.quadraticCurveTo(0.4, 3.0, -0.4 + s * 0, 3.0); c.lineTo(-0.9, 3.0); c.quadraticCurveTo(-1.3, 2.9, -1.2, 2.5); c.lineTo(-0.4, 2.2); c.lineTo(-0.4, 0);
    const h = mesh(extrude(c, 4.0, { bevel: 0.12 }), black);
    h.position.set(s * 3.2, 0.5, 0); h.scale.x = -s;
    parts.push(h);
  }
  const rod = at(group([mesh(rcyl(0.6, 10, 0.25), mat.plastic(TQ_TEAL, { roughness: 0.4 }), { rot: [0, 0, -Math.PI / 2], pos: [-5, 0, 0] })]), 0, 2.15, 0);
  rod.rotation.y = Math.PI / 2;
  parts.push(rod);
  // white "TIME" strap across the top
  const tt = canvasTex(512, 160, (g, w, h) => { g.fillStyle = '#f4f4f0'; rr(g, 0, 0, w, h, 18); g.fill(); txt(g, 'TIME', w * 0.06, h * 0.62, { size: 64, weight: 800, color: '#c4122f' }); txt(g, '14:32', w * 0.45, h * 0.66, { size: 70, weight: 700, color: '#1b1f23', font: '"JetBrains Mono", monospace' }); });
  parts.push(decal(5.6, 1.75, tt, { pos: [0, 0.62, 0], rot: [-Math.PI / 2, 0, 0] }));
  return group(parts);
}
/* ── venous tourniquet: blue elastic strap + quick-release buckle ── */
function venousTourniquet() {
  const blue = mat.matte(0x2f6fd0, { roughness: 0.75, normalMap: NT.crepe([6, 1]), normalScale: new THREE.Vector2(0.4, 0.4) });
  const parts = [];
  const pts = [];
  for (let i = 0; i <= 60; i++) { const a = i / 60 * TAU * 0.92 + 0.25; pts.push(V3(Math.cos(a) * 6.2, 0.1 + Math.max(0, Math.sin(a * 2)) * 0.3, Math.sin(a) * 4.2)); }
  parts.push(mesh(strap(pts, 2.6, 0.14, { up: V3(0, 1, 0), steps: 200 }), blue));
  // free tail out of the buckle
  parts.push(mesh(strap([V3(6.0, 0.35, 1.5), V3(8.5, 0.12, 2.6), V3(11, 0.08, 2.3)], 2.6, 0.14, { up: V3(0, 1, 0) }), blue));
  const buckle = group([
    mesh(rbox(3.2, 1.2, 3.4, 0.45, 3), mat.plastic(0x3a3f45, { roughness: 0.45 })),
    mesh(rbox(1.6, 0.4, 2.0, 0.3, 3), mat.plastic(0x2f6fd0, { roughness: 0.4 }), { pos: [0, 0.65, 0] }),
  ]);
  buckle.position.set(6.1, 0.6, 1.2); buckle.rotation.y = deg(-20);
  parts.push(buckle);
  return group(parts);
}
/* ── long bone (tibia) ── */
function bone() {
  const ivory = mat.matte(0xe9dfc6, { roughness: 0.62, normalMap: NT.plaster([2, 6]), normalScale: new THREE.Vector2(0.5, 0.5) });
  const prof = [[0.001, 0], [0.9, 0.05], [1.35, 0.4], [1.5, 1.2], [1.25, 2.4], [0.85, 4], [0.75, 7], [0.78, 10], [0.95, 12.5], [1.6, 14.4], [2.2, 15.4], [2.3, 16.2], [2.0, 16.7], [0.001, 16.8]];
  const shaft = mesh(lathe(prof, { seg: 48, smooth: 120 }), ivory);
  const parts = [shaft];
  // condyles + tibial tuberosity + malleolus
  for (const s of [-1, 1]) parts.push(mesh(new THREE.SphereGeometry(1.25, 32, 20), ivory, { pos: [s * 1.1, 15.9, 0], scale: [1, 0.7, 1.15] }));
  parts.push(mesh(new THREE.SphereGeometry(0.7, 24, 16), ivory, { pos: [0, 13.6, 1.0], scale: [1, 1.4, 0.8] }));
  parts.push(mesh(new THREE.SphereGeometry(0.6, 24, 16), ivory, { pos: [0.9, 0.7, 0], scale: [0.8, 1.6, 0.9] }));
  const g = group(parts);
  g.rotation.z = Math.PI / 2;
  g.position.y = 1.8;
  return yaw(group([g]), 0);
}
/* ── IV extension line: coil + luer ends + slide clamp ── */
function extensionLine() {
  const parts = [];
  parts.push(tubingCoil({ r: 3.6, turns: 1.8, tubeR: 0.24, lead: [[6, 0.3, 2.5], [9, 0.3, 4.2]] }));
  parts.push(mesh(lathe([[0.25, 0], [0.45, 0.2], [0.45, 1.6], [0.6, 1.8], [0.6, 2.4], [0.3, 2.6]], { seg: 32 }), mat.plastic(0xf3f3f0), { pos: [9, 0.6, 4.2], rot: [0, 0, -Math.PI / 2, 'XYZ'] }));
  parts.push(mesh(rcyl(0.62, 0.9, 0.12), mat.plastic(0x2f7fd8), { pos: [11.4, 0.6, 4.2], rot: [0, 0, -Math.PI / 2] }));
  parts.push(mesh(rbox(1.8, 0.7, 1.0, 0.2, 2), mat.plastic(0xf2f2ee), { pos: [4.2, 0.55, -2.2], rot: [0, 0.6, 0] }));
  // needle-free port at the start of the coil
  parts.push(mesh(lathe([[0.3, 0], [0.5, 0.2], [0.5, 1.2], [0.42, 1.4], [0.42, 1.9], [0.001, 1.9]], { seg: 32 }), mat.plastic(0xf3f3f0), { pos: [3.6, 0.5, 0], rot: [Math.PI / 2, 0, 0] }));
  parts.push(mesh(rcyl(0.36, 0.25, 0.08), mat.rubber(0x6c7176), { pos: [3.6, 0.5, -1.95], rot: [Math.PI / 2, 0, 0] }));
  return group(parts);
}
/* ── plastic measuring ruler ── */
function ruler() {
  const tex = canvasTex(1536, 320, (g, w, h) => {
    g.fillStyle = '#f7f9f8'; g.fillRect(0, 0, w, h);
    g.fillStyle = TEAL; g.fillRect(0, h * 0.78, w, h * 0.22);
    g.fillStyle = '#1b1f23';
    for (let i = 0; i <= 150; i++) { const x = w * 0.03 + i * (w * 0.94 / 150); const L = i % 10 === 0 ? 0.36 : i % 5 === 0 ? 0.24 : 0.14; g.fillRect(x - 1.5, 0, 3, h * L); if (i % 10 === 0) txt(g, String(i / 10), x, h * 0.58, { size: 44, weight: 600, color: '#1b1f23', align: 'center', font: '"Inter", sans-serif' }); }
    txt(g, 'cm', w * 0.95, h * 0.58, { size: 36, weight: 600, color: '#555', align: 'right' });
    txt(g, 'WOUND MEASURING GUIDE', w * 0.04, h * 0.94, { size: 40, weight: 800, color: '#fff' });
  });
  const m = mesh(rbox(16, 0.18, 3.3, 0.06, 2), [mat.plastic(0xf2f4f3), mat.plastic(0xf2f4f3), mat.printed(tex, { roughness: 0.35 }), mat.plastic(0xe9ecea), mat.plastic(0xf2f4f3), mat.plastic(0xf2f4f3)], { pos: [0, 0.09, 0] });
  return group([m]);
}
/* ── wound / bullet probe ── */
function probe() {
  const parts = [];
  parts.push(mesh(new THREE.CylinderGeometry(0.5, 0.42, 6.5, 32).rotateZ(Math.PI / 2), mat.steel({ roughness: 0.45, normalMap: NT.knurl([6, 2]), normalScale: new THREE.Vector2(1, 1) }), { pos: [-6.2, 0.5, 0] }));
  parts.push(mesh(new THREE.CylinderGeometry(0.42, 0.14, 1.2, 24).rotateZ(Math.PI / 2), mat.steel(), { pos: [-2.4, 0.5, 0] }));
  parts.push(mesh(cyl(0.14, 10, { seg: 16 }), mat.steel({ roughness: 0.15 }), { pos: [-1.8, 0.5, 0], rot: [0, 0, -Math.PI / 2] }));
  parts.push(mesh(new THREE.SphereGeometry(0.26, 20, 14), mat.chrome(), { pos: [8.2, 0.5, 0] }));
  return group(parts);
}
/* ── surgical skin marker ── */
function skinMarker() {
  const purple = mat.plastic(0x6d3fc0, { roughness: 0.35 });
  const white = mat.plastic(0xf5f5f3, { roughness: 0.35 });
  const lab = canvasTex(1024, 200, (g, w, h) => { g.fillStyle = '#f5f5f3'; g.fillRect(0, 0, w, h); txt(g, 'SKIN MARKER', w * 0.08, h * 0.62, { size: 74, weight: 800, color: '#5a32a8' }); txt(g, 'STERILE  ·  GENTIAN VIOLET INK', w * 0.55, h * 0.6, { size: 34, weight: 600, color: '#555' }); });
  const parts = [];
  const pen = group([mesh(rcyl(0.55, 10, 0.2), white), mesh(lathe([[0.45, 0], [0.3, 0.8], [0.12, 1.4], [0.08, 1.6], [0.001, 1.65]], { seg: 24 }), mat.matte(0x3d2a6b)), mesh(rcyl(0.5, 1.2, 0.15), purple, { pos: [0, -0.9, 0] })]);
  pen.children[1].position.y = 10;
  pen.rotation.z = -Math.PI / 2; pen.position.set(-5, 0.55, 0);
  parts.push(pen);
  // cap lying beside
  const cap = mesh(lathe([[0.001, 0], [0.55, 0], [0.62, 0.1], [0.62, 3.2], [0.5, 3.4], [0.001, 3.45]], { seg: 32 }), purple, { pos: [1.5, 0.62, 2.4], rot: [0, 0, -Math.PI / 2 - 0.05] });
  parts.push(cap);
  parts.push(mesh(rbox(0.25, 0.5, 2.2, 0.1, 2), purple, { pos: [3.5, 1.1, 2.4] }));
  // printed label along the barrel (decal on top)
  parts.push(decal(7.5, 0.9, lab, { pos: [0.2, 1.11, 0], rot: [-Math.PI / 2, 0, 0], rough: 0.4 }));
  return group(parts);
}
/* ── pen light ── */
function penlight() {
  const body = mat.satin({ roughness: 0.25 });
  const parts = [];
  const g = group([
    mesh(rcyl(0.6, 11, 0.15), mat.plastic(0xf4f5f4, { roughness: 0.35 })),
    mesh(rcyl(0.62, 1.4, 0.12), body, { pos: [0, 10.5, 0] }),
    mesh(new THREE.CylinderGeometry(0.45, 0.45, 0.2, 24), new THREE.MeshStandardMaterial({ color: 0xfff4c8, emissive: 0xfff0b8, emissiveIntensity: 2.4, roughness: 0.2 }), { pos: [0, 11.95, 0] }),
    mesh(rcyl(0.45, 0.6, 0.15), body, { pos: [0, -0.5, 0] }),
  ]);
  // pocket clip
  g.add(mesh(rbox(0.5, 5.5, 0.2, 0.08, 2), body, { pos: [0, 7.8, 0.75] }));
  g.add(mesh(new THREE.SphereGeometry(0.28, 16, 12), body, { pos: [0, 5.2, 0.8] }));
  g.rotation.set(0, 0, -Math.PI / 2); g.position.set(-5.5, 0.6, 0);
  g.rotation.order = 'XYZ'; g.rotation.x = deg(-80);
  parts.push(g);
  const lab = canvasTex(1024, 160, (c, w, h) => { c.fillStyle = '#f4f5f4'; c.fillRect(0, 0, w, h); for (let i = 0; i < 8; i++) { c.fillStyle = '#1b1f23'; c.beginPath(); c.arc(w * 0.08 + i * w * 0.075, h / 2, 10 + i * 3.5, 0, TAU); c.fill(); } txt(c, 'PUPIL GAUGE  mm', w * 0.72, h * 0.62, { size: 46, weight: 700, color: '#555' }); });
  parts.push(decal(6.4, 0.85, lab, { pos: [-1, 1.21, 0], rot: [-Math.PI / 2, 0, 0], rough: 0.4 }));
  return group(parts);
}
/* ── stopwatch ── */
function stopwatch() {
  const chrome = mat.chrome({ roughness: 0.1 });
  const dial = canvasTex(1024, 1024, (g, w) => {
    g.fillStyle = '#f7f7f4'; g.beginPath(); g.arc(w / 2, w / 2, w / 2, 0, TAU); g.fill();
    g.strokeStyle = '#1b1f23';
    for (let i = 0; i < 60; i++) { const a = i / 60 * TAU, L = i % 5 ? 0.05 : 0.1; g.lineWidth = i % 5 ? 4 : 10; g.beginPath(); g.moveTo(w / 2 + Math.sin(a) * w * 0.46, w / 2 - Math.cos(a) * w * 0.46); g.lineTo(w / 2 + Math.sin(a) * w * (0.46 - L), w / 2 - Math.cos(a) * w * (0.46 - L)); g.stroke(); }
    for (let i = 1; i <= 12; i++) { const a = i / 12 * TAU; txt(g, String(i * 5), w / 2 + Math.sin(a) * w * 0.32, w / 2 - Math.cos(a) * w * 0.32 + 26, { size: 72, weight: 700, color: '#1b1f23', align: 'center', font: '"Inter", sans-serif' }); }
    // sub dial
    g.strokeStyle = '#59626b'; g.lineWidth = 5; g.beginPath(); g.arc(w / 2, w * 0.66, w * 0.1, 0, TAU); g.stroke();
    // hands
    g.strokeStyle = '#c4122f'; g.lineWidth = 12; g.lineCap = 'round'; g.beginPath(); g.moveTo(w / 2 - Math.sin(1.1) * 60, w / 2 + Math.cos(1.1) * 60); g.lineTo(w / 2 + Math.sin(1.1) * w * 0.42, w / 2 - Math.cos(1.1) * w * 0.42); g.stroke();
    g.fillStyle = '#c4122f'; g.beginPath(); g.arc(w / 2, w / 2, 22, 0, TAU); g.fill();
    g.strokeStyle = '#1b1f23'; g.lineWidth = 6; g.beginPath(); g.moveTo(w / 2, w * 0.66); g.lineTo(w / 2 + w * 0.06, w * 0.6); g.stroke();
  });
  const parts = [];
  const caseG = group([
    mesh(rcyl(3.2, 1.2, 0.5, { seg: 72 }), chrome),
    mesh(new THREE.CircleGeometry(2.85, 72), mat.printed(dial, { roughness: 0.3 }), { pos: [0, 1.21, 0], rot: [-Math.PI / 2, 0, 0] }),
    mesh(new THREE.TorusGeometry(2.95, 0.18, 12, 72), chrome, { pos: [0, 1.22, 0], rot: [Math.PI / 2, 0, 0] }),
    // crown + start button + ring
    mesh(cyl(0.45, 0.9, { seg: 24 }), chrome, { pos: [0, 0.6, -3.15], rot: [-Math.PI / 2, 0, 0] }),
    mesh(rcyl(0.6, 0.6, 0.15), chrome, { pos: [0, 0.6, -4.0], rot: [-Math.PI / 2, 0, 0] }),
    mesh(new THREE.TorusGeometry(0.9, 0.18, 10, 40), chrome, { pos: [0, 0.6, -5.0], rot: [0, 0, 0] }),
    mesh(cyl(0.3, 0.5, { seg: 16 }), chrome, { pos: [2.4, 0.6, -2.3], rot: [-Math.PI / 2, 0, -0.75, 'YXZ'] }),
  ]);
  caseG.rotation.x = deg(62); caseG.position.y = 3.2;
  parts.push(caseG);
  return group(parts);
}
/* ── endotracheal tube holder: lip plate, bite block, clamp with the tube through it, neck straps ── */
function tubeHolder() {
  const parts = [];
  const white = mat.plastic(0xf2f4f3, { roughness: 0.35 });
  const p = mesh(extrude(rrectShape(10, 3.4, 1.4), 0.45, { bevel: 0.14 }), white);
  bend(p.geometry, v => { v.z -= Math.pow(v.x / 5, 2) * 1.6; });
  p.position.set(0, 1.9, 0);
  parts.push(p);
  parts.push(mesh(rbox(2.6, 2.4, 3.0, 0.6, 3), white, { pos: [0, 1.2, 1.6] }));
  // clamp ring + screw, the tube passing through it
  parts.push(mesh(new THREE.TorusGeometry(0.95, 0.3, 14, 40), mat.plastic(0x2f6fd8, { roughness: 0.35 }), { pos: [0, 3.5, 1.4] }));
  parts.push(mesh(rcyl(0.38, 1.6, 0.12), mat.plastic(0x2f6fd8), { pos: [1.2, 3.6, 1.4], rot: [0, 0, -Math.PI / 2] }));
  const tb = mesh(cyl(0.62, 9, { seg: 32 }), clearMat({ color: 0x2c4654, spec: 0xe4f4fa, roughness: 0.06, opacity: 0.28, lum: 0.95, envMapIntensity: 1.6 }), { pos: [0, 3.5, -3.6], rot: [Math.PI / 2, 0, 0], order: 4 });
  parts.push(tb);
  parts.push(mesh(cyl(0.09, 9, { seg: 8 }), mat.plastic(0x2f6fd8), { pos: [0, 4.12, -3.6], rot: [Math.PI / 2, 0, 0] }));
  parts.push(mesh(lathe([[0.62, 0], [0.9, 0.1], [0.9, 0.6], [0.72, 0.7], [0.72, 1.8], [0.6, 1.9]], { seg: 32 }), white, { pos: [0, 3.5, 5.4], rot: [Math.PI / 2, 0, 0] }));
  // padded neck straps either side
  for (const sgn of [-1, 1]) parts.push(mesh(strap([V3(sgn * 4.8, 1.9, -1.4), V3(sgn * 6.4, 0.9, -2.2), V3(sgn * 8.4, 0.14, -1.6), V3(sgn * 9.6, 0.12, -0.2)], 2.4, 0.25, { up: V3(0, 1, 0) }), mat.fabric(0xe9e6dc, { normalMap: NT.velcro([4, 1]) })));
  return group(parts);
}
/* ── diascope (clear glass plate) ── */
function diascope() {
  const parts = [];
  parts.push(mesh(rbox(9, 0.45, 5.5, 0.2, 3), clearMat({ color: 0x0d1416, spec: 0xd8f0f8, roughness: 0.03, opacity: 0.14, lum: 0.95, envMapIntensity: 1.7 }), { pos: [0, 0.23, 0], order: 4 }));
  const fr = canvasTex(512, 512, (g, w) => { g.fillStyle = 'rgba(245,247,248,.95)'; g.fillRect(0, 0, w, w); txt(g, 'DIASCOPE', w / 2, w * 0.56, { size: 70, weight: 800, color: '#2a3036', align: 'center' }); });
  parts.push(decal(2.6, 5.3, fr, { pos: [-3.1, 0.465, 0], rot: [-Math.PI / 2, 0, Math.PI / 2], rough: 0.8 }));
  return group(parts);
}

export const TOOLS = {
  // sharps
  needle: { view: V(0, 30), build: () => { const n = hypoNeedle({ len: 6, hub: 0xe2668f, hubLen: 1.8 }); n.scale.setScalar(1.5); const cap = mesh(lathe([[0.3, 0], [0.26, 0.3], [0.2, 6.2], [0.14, 6.6], [0.001, 6.62]], { seg: 32 }), mat.plastic(0xe2668f, { roughness: 0.4 }), { rot: [0, 0, -Math.PI / 2], pos: [-1, 0.45, 2.4] }); cap.scale.setScalar(1.4); return yaw(group([at(n, 0, 0.5, 0), cap]), 40); } },
  'needle-driver': { view: V(0, 34), build: () => { const h = hemostat({ len: 14, curved: false, gold: true, open: 0.05, jaw: 2.4 }); const nd = sutureNeedle({ r: 1.1, threadLen: 1.2 }); nd.position.set(1.95, 0.12, -0.89); nd.rotation.y = Math.PI / 2; h.add(nd); return yaw(h, 42); } },
  cannula: { view: V(0, 32), build: () => yaw(ivCannula({ gauge: 20, len: 4.4 }), 40) },
  syringe: { view: V(0, 30), build: () => yaw(syringe({ len: 7.5, r: 0.72, ml: 10, fill: 0.55, liquid: 0x2a2c2e, needle: { hub: 0x2f7fd8, len: 3.2, gauge: 0.04 } }), 40) },
  drop: {
    view: V(0, 32),
    build: () => {
      const lab = drugLabel({ w: 1024, h: 240, name: 'SODIUM CHLORIDE 0.9%', strength: 'FLUSH  ·  30 mL', sub: 'STERILE  ·  SINGLE USE', band: '#1f62c4', seed: 141 });
      const s = syringe({ len: 9.5, r: 1.05, ml: 30, fill: 0.85, liquid: 0x1d3f5c, label: lab, plunger: 0xf4f5f6 });
      return yaw(s, 40);
    },
  },
  scalpel: { view: V(0, 52), build: () => yaw(scalpel({ len: 12 }), 36) },
  forceps: { view: V(0, 36), build: () => yaw(hemostat({ len: 14, curved: true, open: 0.2 }), 42) },
  scissors: { view: V(0, 36), build: () => yaw(scissors({ len: 14, open: 0.25 }), 42) },
  probe: { view: V(0, 34), build: () => yaw(probe(), 40) },

  // dressings
  gauze: { view: V(30, 34), build: () => gauzeStack({ n: 3, w: 9, d: 9 }) },
  'gauze-roll': { view: V(30, 30), build: () => yaw(gauzeRoll({ r: 2.6, w: 6.5, tail: 5 }), -18) },
  bandage: { view: V(30, 30), build: () => yaw(bandageRoll({ r: 2.3, w: 7.5, tail: 4.5 }), -18) },
  'dressing-pad': { view: V(28, 38), build: () => yaw(islandDressing({ w: 11, d: 9 }), -14) },

  // bleeding control / restraint
  'tq-strap': { view: V(30, 32), build: ({ loadGLB }) => loadGLB('nz_amb_tourniquet') },
  refresh: { view: V(30, 34), build: () => yaw(windlass(), -30) },          // treat: tourniquet 'Windlass' step
  'tq-clip': { view: V(30, 36), build: () => yaw(tqClip(), -20) },
  clamp: { view: V(28, 38), build: () => yaw(venousTourniquet(), -10) },     // IV / donation: venous tourniquet / line clamp
  cuff: { view: V(30, 30), build: ({ loadGLB }) => loadGLB('nz_amb_binder_worn') }, // pelvic binder (also BP cuff, splint straps)
  gauge: { view: V(24, 22), build: ({ loadGLB }) => loadGLB('nz_amb_infuser') },   // pressure infuser / cuff with gauge + bulb

  // access & fluids
  drill: { view: V(-32, 22), build: ({ loadGLB }) => loadGLB('nz_amb_iodrill') },
  bone: { view: V(0, 34), build: () => yaw(bone(), 40) },
  tube: { view: V(24, 40), build: () => extensionLine() },
  iv: { view: V(22, 18), build: () => salineBag() },
  bloodbag: { view: V(22, 18), build: () => bloodBag() },
  bottle: { view: V(28, 24), build: () => salineBottle({ theta: deg(28) }) },
  flask: { view: V(30, 24), build: () => contrastBottle({ theta: deg(30) }) },
  spring: { view: V(10, 44), build: () => { const c = emboCoil({ wire: true }); c.scale.setScalar(1.2); return c; } },

  // wraps / immobilisation / imaging
  blanket: { view: V(30, 32), build: () => yaw(foilBlanket({ w: 12, d: 9, t: 1.6 }), -20) },
  collar: { view: V(30, 26), build: ({ loadGLB }) => loadGLB('nz_amb_collar') },
  splint: { view: V(28, 34), build: ({ loadGLB }) => loadGLB('nz_amb_splint_arm') },
  ruler: { view: V(0, 40), build: () => yaw(ruler(), 30) },
  xray: { view: V(18, 44), build: () => { const f = xrayFilm({ w: 14, d: 17 }); f.children[0].geometry = bend(f.children[0].geometry.clone(), v => { v.y += Math.pow(Math.max(0, v.x / 7), 2) * 0.9; }); return yaw(f, -10); } },
  'us-probe': { view: V(30, 22), build: ({ loadGLB }) => loadGLB('nz_amb_us_probe') },

  // monitoring
  stetho: { view: V(20, 44), build: ({ loadGLB }) => loadGLB('nz_amb_stethoscope') },
  monitor: { view: V(30, 22), build: ({ loadGLB }) => loadGLB('nz_amb_monitor') },
  defib: { view: V(10, 44), build: () => defibPads() },
  timer: { view: V(10, 22), build: () => stopwatch() },
  light: { view: V(0, 34), build: () => yaw(penlight(), 40) },
  edit: { view: V(0, 34), build: () => yaw(skinMarker(), 40) },

  // suction / chest
  wind: { view: V(10, 34), build: () => yaw(yankauer(), 34) },
  kit: { view: V(28, 20), build: () => drainUnit() },

  // airway (intubation app)
  'itb-bvm': { view: V(34, 30), build: ({ loadGLB }) => loadGLB('nz_amb_bvm') },
  'itb-scope': { view: V(30, 22), build: async ({ loadGLB }) => { const l = await loadGLB('nz_amb_laryngoscope'); return yaw(group([l]), -20); } },
  'itb-suction': { view: V(10, 34), build: () => yaw(yankauer(), 34) },
  'itb-tube': { view: V(10, 36), build: () => yaw(ett({ len: 18 }), -30) },
  'itb-holder': { view: V(24, 30), build: () => tubeHolder() },

  // burn / skin graft
  'bn-diascope': { view: V(20, 40), build: () => yaw(diascope(), -18) },
  'bn-dermatome': { view: V(0, 30), build: () => yaw(dermatome(), 38) },
  'bn-mesher': { view: V(30, 30), build: () => mesher() },
  'bn-stapler': { view: V(14, 20), build: () => yaw(skinStapler(), -4) },
};
