// Inventory item models: one entry per item name in config/items.lua (Config.Items values) + nza_unknown.
// Each entry: { build: async ({ loadGLB }) => Object3D, view: { az, elev, fill, ... } }  (see studio.js)
// GLB entries reuse the props pipeline exports (tools/props) so the picture matches the in-game prop.
import {
  THREE, V3, deg, mat, mesh, group, rbox, lathe, cyl, rcyl, tube, strap, pillow, extrude, rrectShape, rrectPath, circlePath,
  wrapLabel, decal, canvasTex, txt, rr, NT, clearMat, cross, starOfLife, barcode, datamatrix, finePrint, rng, merge, bend,
} from '../lib.js';
import { drugLabel, boxFront } from '../labels.js';
import { vial, ampoule, syringe, roll, hardCase, fluidBag, sachet, peelPouch, tubingCoil, tablet, hemostat, scalpel, thumbForceps, sutureNeedle, ivCannula, hypoNeedle, card, TAU } from '../parts.js';
import {
  TEAL, bandageRoll, gauzeStack, gauzePad, islandDressing, sachetTex, salineBottle, contrastBottle, salineBag, bloodBag, bloodLabel,
  foilBlanket, xrayFilm, emboCoil, ett, yankauer, dermatome, mesher, skinStapler,
} from './common.js';

const V = (az = 32, elev = 30, extra = {}) => ({ az, elev, ...extra });
const yaw = (o, d) => { o.rotation.y = deg(d); return o; };
const at = (o, x, y, z) => { o.position.set(x, y, z); return o; };

/* small printed carton (front/back faces printed) */
function carton({ w, h, d, front, side = null, color = 0xf7f7f4 }) {
  const plain = mat.matte(color, { roughness: 0.6 });
  const fm = mat.printed(front, { roughness: 0.5, clearcoat: 0.2 });
  const sm = side ? mat.printed(side, { roughness: 0.5, clearcoat: 0.2 }) : plain;
  return mesh(rbox(w, h, d, Math.min(w, h, d) * 0.04, 2), [sm, sm, plain, plain, fm, plain], { pos: [0, h / 2, 0] });
}

export const ITEMS = {
  /* ───────────── first aid ───────────── */
  bandage: { view: V(30, 30), build: () => yaw(bandageRoll({ r: 2.3, w: 7.5, tail: 5.2 }), -18) },

  gauze: {
    view: V(30, 32),
    build: () => {
      const tex = sachetTex({ title: 'GAUZE SWABS', line2: '10 x 10 cm  ·  8 PLY', line3: '5 SWABS  ·  100% COTTON  ·  SINGLE USE', icon: (g, w, h) => { g.strokeStyle = '#0c8a83'; g.lineWidth = 8; g.strokeRect(w * 0.62, h * 0.24, w * 0.24, w * 0.24); for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(w * 0.62 + i * w * 0.06, h * 0.24); g.lineTo(w * 0.62 + i * w * 0.06, h * 0.24 + w * 0.24); g.moveTo(w * 0.62, h * 0.24 + i * w * 0.06); g.lineTo(w * 0.86, h * 0.24 + i * w * 0.06); g.stroke(); } } });
      const pack = yaw(sachet({ w: 12, h: 14, t: 0.9, tex }), 12);
      at(pack, -2.5, 0, -2.5);
      const pads = yaw(gauzeStack({ n: 3, w: 9, d: 9 }), -20);
      at(pads, 4.5, 0, 4);
      return group([pack, pads]);
    },
  },

  tourniquet: { view: V(30, 32, { fill: 0.82 }), build: ({ loadGLB }) => loadGLB('nz_amb_tourniquet') },

  ice_pack: {
    view: V(25, 34),
    build: () => {
      const tex = canvasTex(1024, 1400, (g, w, h) => {
        const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#2f8fe0'); gr.addColorStop(0.45, '#7cc4f2'); gr.addColorStop(1, '#eaf6fd');
        g.fillStyle = gr; g.fillRect(0, 0, w, h);
        g.fillStyle = 'rgba(255,255,255,.9)'; g.fillRect(0, 0, w, h * 0.05); g.fillRect(0, h * 0.95, w, h * 0.05);
        // snowflake
        g.save(); g.translate(w / 2, h * 0.33); g.strokeStyle = '#fff'; g.lineWidth = 26; g.lineCap = 'round';
        for (let k = 0; k < 6; k++) { g.rotate(Math.PI / 3); g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -210); g.moveTo(0, -120); g.lineTo(-60, -175); g.moveTo(0, -120); g.lineTo(60, -175); g.stroke(); }
        g.restore();
        txt(g, 'INSTANT', w / 2, h * 0.6, { size: 96, weight: 800, color: '#0d3d6e', align: 'center' });
        txt(g, 'COLD PACK', w / 2, h * 0.68, { size: 96, weight: 800, color: '#0d3d6e', align: 'center' });
        txt(g, 'SQUEEZE  ·  SHAKE  ·  APPLY', w / 2, h * 0.75, { size: 40, weight: 600, color: '#1b5c96', align: 'center' });
        finePrint(g, w * 0.15, h * 0.8, w * 0.7, 3, { h: 10, gap: 14, seed: 15, color: 'rgba(13,61,110,.45)' });
      });
      return yaw(sachet({ w: 12, h: 17, t: 4.4, tex, seam: 0.9, rough: 0.3, back: 0xe8f3fb }), -16);
    },
  },

  medikit: {
    view: V(30, 30),
    build: () => {
      const front = canvasTex(512, 184, (g, w, h) => { g.clearRect(0, 0, w, h); rr(g, 0, 0, w, h, 18); g.fillStyle = '#ffffff'; g.fill(); cross(g, h * 0.55, h / 2, h * 0.7, '#d2202c'); txt(g, 'FIRST AID', h * 1.05, h * 0.5, { size: h * 0.27, weight: 800, color: '#c41a26', base: 'middle' }); txt(g, 'KIT', h * 1.05, h * 0.78, { size: h * 0.16, weight: 600, color: '#555', base: 'middle' }); });
      return hardCase({ w: 30, h: 11, d: 20, color: 0xd11f2d, front });
    },
  },

  painkillers: {
    view: V(28, 26),
    build: () => {
      const r = 2.1, h = 6.6;
      const parts = [];
      parts.push(mesh(lathe([[0.001, 0], [r * 0.9, 0], [r, 0.2], [r, h * 0.86], [r * 0.9, h * 0.9], [r * 0.88, h * 0.94], [0.001, h * 0.94]], { seg: 72 }), clearMat({ color: 0xb4621c, roughness: 0.18, opacity: 0.82, lum: 0.55 }), { order: 4 }));
      // tablets inside (seen through the amber)
      const R = rng(4);
      for (let i = 0; i < 22; i++) { const t = tablet({ r: 0.5, t: 0.26, score: false }); const a = R() * TAU, d = R() * (r - 0.6); t.position.set(Math.cos(a) * d, 0.2 + R() * h * 0.45, Math.sin(a) * d); t.rotation.set(R() * 3, R() * 3, R() * 3); parts.push(t); }
      // child-resistant cap
      parts.push(mesh(rcyl(r * 1.04, 1.5, 0.18, { y: h * 0.86 }), mat.plastic(0xf6f6f4, { roughness: 0.4, normalMap: NT.ribs([1, 24]), normalScale: new THREE.Vector2(0.6, 0.6) })));
      const lab = drugLabel({ w: 1024, h: 420, name: 'PAIN RELIEF', strength: 'PARACETAMOL 500 mg', sub: '24 TABLETS  ·  ORAL  ·  READ THE LEAFLET', band: TEAL, bandText: 'TABLETS', seed: 22, window: 1 });
      parts.push(wrapLabel(r + 0.015, h * 0.16, h * 0.72, lab, { theta: deg(28), len: TAU * 0.58, focus: 0.37 }));
      // two tablets on the table
      parts.push(at(yaw(tablet({ r: 0.62, t: 0.32 }), 30), 3.2, 0, 2.2));
      parts.push(at(yaw(tablet({ r: 0.62, t: 0.32 }), -50), 1.6, 0, 3.3));
      return group(parts);
    },
  },

  burn_dressing: {
    view: V(28, 34),
    build: () => {
      const tex = sachetTex({ title: 'BURN DRESSING', line2: 'HYDROGEL  ·  10 x 10 cm', line3: 'COOLS  ·  SOOTHES  ·  PROTECTS', band: '#e2621b', bg: '#d6dadd', foil: true, icon: (g, w, h) => { g.fillStyle = '#2f8fd8'; g.beginPath(); g.moveTo(w * 0.78, h * 0.22); g.bezierCurveTo(w * 0.86, h * 0.3, w * 0.88, h * 0.34, w * 0.78, h * 0.38); g.bezierCurveTo(w * 0.68, h * 0.34, w * 0.7, h * 0.3, w * 0.78, h * 0.22); g.fill(); } });
      return yaw(sachet({ w: 12, h: 14, t: 0.8, tex, foil: true, back: 0xc5cacd }), -14);
    },
  },

  sterile_dressing: {
    view: V(30, 34),
    build: () => {
      const tex = sachetTex({ title: 'ADHESIVE DRESSING', line2: '10 x 15 cm  ·  ISLAND PAD', line3: 'LOW ADHERENT  ·  BREATHABLE', band: '#2f7fd8' });
      const pack = at(yaw(sachet({ w: 11, h: 14, t: 0.5, tex }), 16), -3.2, 0, -2.8);
      const d = at(yaw(islandDressing({ w: 11, d: 9 }), -22), 3.2, 0.05, 3.4);
      return group([pack, d]);
    },
  },

  foil_blanket: {
    view: V(30, 32),
    build: () => {
      const tex = canvasTex(512, 256, (g, w, h) => { g.fillStyle = 'rgba(255,255,255,.92)'; rr(g, 0, 0, w, h, 16); g.fill(); txt(g, 'RESCUE BLANKET', w * 0.06, h * 0.38, { size: 52, weight: 800, color: '#1b1f23', max: w * 0.88 }); txt(g, '160 x 210 cm  ·  GOLD / SILVER', w * 0.06, h * 0.62, { size: 26, weight: 600, color: '#555', max: w * 0.88 }); finePrint(g, w * 0.06, h * 0.76, w * 0.7, 2, { h: 6, gap: 8, seed: 8 }); });
      const fb = foilBlanket({ w: 12, d: 9, t: 1.6 });
      fb.add(decal(6, 3, tex, { pos: [-2.4, 1.63, -1.6], rot: [-Math.PI / 2, 0, 0] }));
      return yaw(fb, -20);
    },
  },

  /* ───────────── wound care & surgery ───────────── */
  suture_kit: {
    view: V(25, 36),
    build: () => {
      const tex = canvasTex(800, 1200, (g, w, h) => {
        g.fillStyle = '#f4f3ee'; g.fillRect(0, 0, w, h);
        g.fillStyle = '#1d4fa3'; g.fillRect(0, 0, w, h * 0.12);
        txt(g, 'SUTURE', w * 0.08, h * 0.085, { size: 70, weight: 800, color: '#fff', spacing: 4 });
        txt(g, '4-0', w * 0.08, h * 0.27, { size: 150, weight: 800, color: '#1d4fa3' });
        txt(g, 'NON-ABSORBABLE', w * 0.08, h * 0.34, { size: 46, weight: 700, color: '#16191d' });
        txt(g, 'MONOFILAMENT  ·  45 cm', w * 0.08, h * 0.39, { size: 36, weight: 600, color: '#3b4247' });
        // needle drawing
        g.strokeStyle = '#16191d'; g.lineWidth = 10; g.beginPath(); g.arc(w * 0.5, h * 0.62, w * 0.22, Math.PI * 1.05, Math.PI * 1.95); g.stroke();
        txt(g, '3/8 CIRCLE  ·  19 mm  ·  REVERSE CUTTING', w * 0.5, h * 0.7, { size: 30, weight: 600, color: '#3b4247', align: 'center' });
        g.fillStyle = '#1d4fa3'; g.fillRect(0, h * 0.94, w, h * 0.06);
        barcode(g, w * 0.08, h * 0.78, w * 0.5, h * 0.1, 71);
        txt(g, 'STERILE', w * 0.66, h * 0.85, { size: 40, weight: 800, color: '#1d4fa3' });
      });
      const pack = mesh(rbox(8, 0.25, 12, 0.08, 2), [mat.matte(0xe9e8e2), mat.matte(0xe9e8e2), mat.printed(tex, { roughness: 0.55 }), mat.matte(0xe9e8e2), mat.matte(0xe9e8e2), mat.matte(0xe9e8e2)], { pos: [0, 0.125, 0] });
      const p2 = mesh(rbox(8, 0.25, 12, 0.08, 2), [mat.matte(0xe9e8e2), mat.matte(0xe9e8e2), mat.printed(tex, { roughness: 0.55 }), mat.matte(0xe9e8e2), mat.matte(0xe9e8e2), mat.matte(0xe9e8e2)], { pos: [-1.8, 0.125, -2.2], rot: [0, deg(-14), 0] });
      p2.position.y = 0.125; pack.position.y = 0.375;
      const packs = yaw(group([p2, pack]), 14);
      const nh = hemostat({ len: 14, curved: false, gold: false, open: 0.05, jaw: 2.4 });
      const nd = sutureNeedle({ r: 1.1, threadLen: 1.3 });
      nd.position.set(1.95, 0.12, -0.89); nd.rotation.y = Math.PI / 2;
      nh.add(nd);
      at(yaw(nh, 34), 2.2, 0.55, 3.2);
      return group([packs, nh]);
    },
  },

  saline: { view: V(28, 24), build: () => salineBottle({ theta: deg(28) }) },

  lidocaine: {
    view: V(30, 24),
    build: () => {
      const lab = drugLabel({ name: 'LIDOCAINE 2%', strength: '20 mg/mL  ·  20 mL', sub: 'LOCAL ANAESTHETIC  ·  FOR INFILTRATION', band: '#5d6670', bandText: 'INJECTION', window: 1, seed: 13 });
      return vial({ r: 1.5, h: 5.8, cap: 0x8e979f, label: lab, theta: deg(30), fill: 0.58 });
    },
  },

  iodine_swab: {
    view: V(28, 36),
    build: () => {
      const tex = sachetTex({ title: 'POVIDONE-IODINE', line2: '10%  ·  ANTISEPTIC SWABSTICKS', line3: '3 SWABSTICKS  ·  EXTERNAL USE ONLY', band: '#8a3d12', icon: (g, w, h) => { g.fillStyle = '#8a3d12'; g.beginPath(); g.ellipse(w * 0.8, h * 0.3, w * 0.07, h * 0.04, 0, 0, TAU); g.fill(); } });
      const pack = at(yaw(sachet({ w: 8, h: 12, t: 0.6, tex }), 18), -3.4, 0, -2.6);
      const stick = (i) => {
        const s = group([
          mesh(cyl(0.16, 11, { seg: 16 }), mat.plastic(0xf4f4f2, { roughness: 0.4 }), { rot: [0, 0, -Math.PI / 2], pos: [-5.5, 0.55, 0] }),
          mesh(lathe([[0.001, 0], [0.42, 0.05], [0.5, 0.4], [0.5, 1.6], [0.36, 2.1], [0.001, 2.2]], { seg: 32, smooth: 30 }), mat.matte(0x7a2f0c, { roughness: 0.95, normalMap: NT.foam([2, 2]), normalScale: new THREE.Vector2(1, 1) }), { rot: [0, 0, -Math.PI / 2], pos: [5.3, 0.55, 0] }),
        ]);
        return s;
      };
      const s1 = at(yaw(stick(0), 32), 2.4, 0, 3.4), s2 = at(yaw(stick(1), 20), 4.2, 0, 1.6);
      s1.scale.setScalar(1.6); s2.scale.setScalar(1.6);
      return group([pack, s1, s2]);
    },
  },

  surgical_kit: {
    view: V(22, 42, { fill: 0.84 }),
    build: () => {
      const steel = mat.satin({ roughness: 0.3 });
      const W = 21, D = 14, H = 2.4;
      const ring = new THREE.Shape(rrectShape(W, D, 2).getPoints(48));
      ring.holes.push(rrectPath(W - 0.5, D - 0.5, 1.8));
      const wall = mesh(extrude(ring, H, { bevel: 0.12 }), steel); wall.rotation.x = -Math.PI / 2; wall.position.y = H / 2;
      const floor = mesh(rbox(W - 0.3, 0.2, D - 0.3, 0.1, 2), steel, { pos: [0, 0.1, 0] });
      const towel = mesh(rbox(W - 1.2, 0.3, D - 1.2, 0.12, 2), mat.fabric(0x2f6fa8, { normalMap: NT.weave([10, 6]) }), { pos: [0, 0.35, 0] });
      const ins = [
        at(yaw(scalpel({ len: 13 }), 0), -1.5, 0.5, -4.4),
        at(yaw(thumbForceps({ len: 14, spread: 1.1 }), 0), 0, 0.5, -1.4),
        at(yaw(hemostat({ len: 14, curved: true, open: 0.15 }), 0), 0.5, 0.5, 2.0),
        at(group([mesh(cyl(0.16, 15, { seg: 12 }), mat.steel(), { rot: [0, 0, -Math.PI / 2], pos: [-7.5, 0.3, 0] }), mesh(new THREE.SphereGeometry(0.28, 16, 12), mat.steel(), { pos: [7.6, 0.3, 0] }), mesh(rbox(5, 0.4, 0.9, 0.15, 2), mat.steel({ roughness: 0.5, normalMap: NT.knurl([8, 1]) }), { pos: [-5, 0.3, 0] })]), 0, 0.5, 5.0),
      ];
      return yaw(group([wall, floor, towel, ...ins]), -8);
    },
  },

  graft_kit: {
    view: V(30, 32),
    build: () => {
      // rigid sterilisation container with a filter lid + the dermatome on top
      const W = 28, H = 9, D = 15;
      const alu = mat.alu(0xbfc5cb, { roughness: 0.32, normalMap: NT.brushed([1, 1]), normalScale: new THREE.Vector2(0.3, 0.3) });
      const parts = [mesh(rbox(W, H, D, 0.8, 4), alu, { pos: [0, H / 2, 0] })];
      const lidTex = canvasTex(1024, 560, (g, w, h) => {
        g.fillStyle = '#2b5fae'; g.fillRect(0, 0, w, h);
        g.fillStyle = '#1f4d93'; for (let y = 0; y < 7; y++) for (let x = 0; x < 14; x++) { g.beginPath(); g.arc(w * 0.12 + x * w * 0.055, h * 0.2 + y * h * 0.1, 10, 0, TAU); g.fill(); }
      });
      parts.push(mesh(rbox(W + 0.4, 1.2, D + 0.4, 0.5, 3), [alu, alu, mat.alu(0xffffff, { map: lidTex, roughness: 0.35, metalness: 0.6 }), alu, alu, alu], { pos: [0, H + 0.5, 0] }));
      for (const s of [-1, 1]) {
        parts.push(mesh(rbox(0.6, 2.2, 3, 0.2, 2), mat.plastic(0x2b2f34), { pos: [s * (W / 2 + 0.3), H * 0.7, 0] }));
        parts.push(mesh(strap([V3(s * (W / 2 + 0.4), H * 0.55, -3), V3(s * (W / 2 + 2.0), H * 0.5, -2), V3(s * (W / 2 + 2.0), H * 0.5, 2), V3(s * (W / 2 + 0.4), H * 0.55, 3)], 0.4, 0.5, { up: V3(0, 1, 0), round: 0.9 }), mat.steel()));
      }
      const tag = canvasTex(640, 300, (g, w, h) => { g.fillStyle = '#f7f7f2'; rr(g, 0, 0, w, h, 18); g.fill(); g.fillStyle = TEAL; g.fillRect(0, 0, w, h * 0.22); txt(g, 'SURGICAL SET', w * 0.06, h * 0.16, { size: 40, weight: 800, color: '#fff' }); txt(g, 'SKIN GRAFT', w * 0.06, h * 0.52, { size: 74, weight: 800, color: '#16191d' }); txt(g, 'DERMATOME · MESHER · STAPLER', w * 0.06, h * 0.72, { size: 30, weight: 600, color: '#3b4247', max: w * 0.88 }); barcode(g, w * 0.06, h * 0.8, w * 0.5, h * 0.13, 81); });
      parts.push(decal(10, 4.7, tag, { pos: [-4, H * 0.48, D / 2 + 0.03] }));
      const dm = at(yaw(dermatome(), -14), 1.5, H + 1.1, 0.5);
      dm.scale.setScalar(0.9);
      parts.push(dm);
      return group(parts);
    },
  },

  /* ───────────── fluids & IV ───────────── */
  iv_kit: {
    view: V(20, 44),
    build: () => {
      const paper = canvasTex(1024, 640, (g, w, h) => { g.fillStyle = '#f3f2ec'; g.fillRect(0, 0, w, h); g.fillStyle = TEAL; g.fillRect(0, 0, w, h * 0.16); txt(g, 'IV START KIT', w * 0.05, h * 0.115, { size: 64, weight: 800, color: '#fff' }); txt(g, 'CANNULA 20 G  ·  1.1 x 32 mm', w * 0.05, h * 0.92, { size: 40, weight: 700, color: '#333' }); finePrint(g, w * 0.55, h * 0.84, w * 0.4, 3, { h: 7, gap: 9, seed: 91 }); });
      const base = mesh(rbox(14, 0.12, 8.5, 0.04, 1), [mat.matte(0xf0efe8), mat.matte(0xf0efe8), mat.paper(paper), mat.matte(0xf0efe8), mat.matte(0xf0efe8), mat.matte(0xf0efe8)], { pos: [0, 0.06, 0] });
      const can = at(yaw(ivCannula({ gauge: 20, len: 4.4 }), 18), 0.5, 0.12, -0.5);
      can.scale.setScalar(2.6);
      const coil = tubingCoil({ r: 2.0, turns: 1.6, tubeR: 0.2, x: 5.0, z: 2.2 });
      coil.position.y = 0.12;
      const clampP = mesh(rbox(1.4, 0.5, 0.9, 0.15, 2), mat.plastic(0xf1f1ee), { pos: [2.8, 0.45, 2.3], rot: [0, 0.4, 0] });
      const cap = mesh(rcyl(0.42, 1.0, 0.1), mat.plastic(0xe2668f), { pos: [-5.2, 0.5, 3.2], rot: [0, 0, Math.PI / 2] });
      return group([base, can, coil, clampP, cap]);
    },
  },

  io_kit: {
    view: V(18, 50),
    build: () => {
      const parts = [];
      const paper = canvasTex(1024, 640, (g, w, h) => { g.fillStyle = '#f3f2ec'; g.fillRect(0, 0, w, h); g.fillStyle = '#c4362d'; g.fillRect(0, 0, w, h * 0.15); txt(g, 'IO NEEDLE SET', w * 0.05, h * 0.11, { size: 60, weight: 800, color: '#fff' }); ['15 mm', '25 mm', '45 mm'].forEach((s, i) => txt(g, s, w * (0.2 + i * 0.3), h * 0.93, { size: 38, weight: 700, color: '#333', align: 'center' })); });
      parts.push(mesh(rbox(16, 0.15, 10, 0.05, 1), [mat.matte(0xf0efe8), mat.matte(0xf0efe8), mat.paper(paper), mat.matte(0xf0efe8), mat.matte(0xf0efe8), mat.matte(0xf0efe8)], { pos: [0, 0.075, 0] }));
      // clear blister
      const bl = mesh(rbox(15.2, 1.8, 7.6, 0.7, 4), clearMat({ color: 0xf2f8fb, roughness: 0.1, opacity: 0.05, lum: 0.28 }), { pos: [0, 1.05, -0.3], order: 5 });
      bl.userData.noShadow = true;
      parts.push(bl);
      [[0xd8343c, 1.5], [0x2f7fd8, 2.5], [0xf2c53d, 4.5]].forEach(([col, nl], i) => {
        const x = -4.8 + i * 4.8;
        const n = group([
          mesh(lathe([[0.001, 0], [0.75, 0], [0.8, 0.1], [0.8, 0.5], [0.45, 0.7], [0.32, 1.3], [0.22, 1.5], [0.001, 1.5]], { seg: 40 }), mat.plastic(col, { roughness: 0.3 })),
          mesh(cyl(0.09, nl * 0.9 + 0.6, { seg: 16, y: 1.5 }), mat.steel({ roughness: 0.12 })),
          mesh(new THREE.ConeGeometry(0.09, 0.3, 3), mat.steel(), { pos: [0, 1.5 + nl * 0.9 + 0.75, 0] }),
        ]);
        n.rotation.x = Math.PI / 2; n.rotation.y = 0; n.position.set(x, 0.95, 2.4);
        n.rotation.order = 'XYZ';
        // lay along -Z (hub at the front)
        n.rotation.set(-Math.PI / 2, 0, 0);
        n.position.set(x, 0.95, 2.6);
        n.scale.setScalar(1.35);
        parts.push(n);
      });
      return yaw(group(parts), -10);
    },
  },

  saline_bag: { view: V(22, 18), build: () => salineBag() },
  blood_bag: { view: V(22, 18), build: () => bloodBag() },

  empty_blood_bag: {
    view: V(18, 50),
    build: () => {
      const parts = [];
      const [f, b] = pillow(11, 15, 0.5, { seam: 0.6, nx: 40, ny: 60, power: 0.7 });
      const film = mat.film({ color: 0xf7f2f2, opacity: 0.3 });
      const bag = group([mesh(f, film, { order: 4 }), mesh(b, film, { order: 4 })]);
      const [lf] = pillow(7.4, 9, 0.52, { seam: 0.01, nx: 16, ny: 16, power: 0.7, ramp: 6 });
      bag.add(mesh(lf, mat.printed(bloodLabel({ empty: true }), { transparent: true, alphaTest: 0.05, polygonOffset: true, polygonOffsetFactor: -2 }), { pos: [0, 0.4, 0.01], order: 5 }));
      bag.rotation.x = -Math.PI / 2; bag.position.y = 0.3;
      parts.push(bag);
      // ports + collection tubing coiled beside, needle cover at the end
      parts.push(mesh(cyl(0.3, 1.4), mat.glass({ opacity: 0.4 }), { pos: [-2, 0.3, -7.6], rot: [-Math.PI / 2, 0, 0] }));
      const coil = tubingCoil({ r: 2.6, turns: 2.2, tubeR: 0.17, x: 7.6, z: 1.5, color: 0xf6eeee, lead: [[4.8, 0.2, -3.4], [1.5, 0.2, -6.4], [-2, 0.3, -7.8]] });
      parts.push(coil);
      parts.push(mesh(rcyl(0.36, 3.2, 0.12), mat.plastic(0x2fa64a, { roughness: 0.35 }), { pos: [9.8, 0.4, 4.2], rot: [0, 0, Math.PI / 2 - 0.3, 'YXZ'] }));
      parts.push(mesh(rbox(1.2, 0.7, 1.6, 0.2, 2), mat.plastic(0xf6f6f3), { pos: [6.0, 0.55, -1.3] }));
      return yaw(group(parts), 12);
    },
  },

  txa: {
    view: V(28, 26),
    build: () => {
      const lab = drugLabel({ w: 1024, h: 420, name: 'TRANEXAMIC ACID', strength: '500 mg / 5 mL', sub: 'IV  ·  SLOW INJECTION', band: '#7a3fc0', bandText: 'AMPOULE', seed: 17 });
      const a1 = ampoule({ r: 0.95, h: 8.2, ring: 0x7a3fc0, label: lab, theta: deg(28), fill: 0.44 });
      const a2 = ampoule({ r: 0.95, h: 8.2, ring: 0x7a3fc0, label: lab, theta: deg(0), fill: 0.44 });
      a2.rotation.set(0, deg(18), Math.PI / 2 - 0.08, 'YXZ'); a2.position.set(2.6, 0.95, 2.4);
      at(a1, -1.6, 0, -0.8);
      return group([a1, a2]);
    },
  },

  /* ───────────── medication ───────────── */
  morphine: {
    view: V(30, 24),
    build: () => {
      const lab = drugLabel({ name: 'MORPHINE', strength: '10 mg/mL', sub: '1 mL  ·  IV / IM  ·  CONTROLLED DRUG', band: '#1f5fbf', bandText: 'INJECTION', window: 1, seed: 11 });
      return vial({ r: 1.15, h: 4.6, cap: 0x2156c4, label: lab, theta: deg(30), fill: 0.5 });
    },
  },

  adrenaline: {
    view: V(0, 32),
    build: () => {
      const lab = drugLabel({ w: 1024, h: 260, name: 'ADRENALINE', strength: '1 mg / 10 mL', sub: '0.1 mg/mL  ·  PRE-FILLED SYRINGE', band: '#c4122f', bandText: '1:10 000', seed: 12 });
      const s = syringe({ len: 10, r: 0.85, ml: 10, fill: 0.92, plunger: 0xe9302f, label: lab, cap: 0xd8262c });
      return yaw(s, 38);
    },
  },

  naloxone: {
    view: V(30, 26),
    build: () => {
      const lab = drugLabel({ name: 'NALOXONE', strength: '0.4 mg/mL', sub: '1 mL  ·  IV / IM / IN  ·  OPIOID ANTAGONIST', band: '#1f9a4c', bandText: 'INJECTION', window: 1, seed: 14, stripes: true });
      const v = at(vial({ r: 1.15, h: 4.6, cap: 0x1f9a4c, label: lab, theta: deg(30), fill: 0.45 }), 1.9, 0, 1.6);
      const front = boxFront({ w: 512, h: 1024, title: 'NALOXONE', line2: '0.4 mg/mL  ·  10 x 1 mL', band: '#1f9a4c', foot: 'INJECTION', seed: 18 });
      const side = canvasTex(256, 1024, (g, w, h) => { g.fillStyle = '#f7f8f6'; g.fillRect(0, 0, w, h); g.fillStyle = '#1f9a4c'; g.fillRect(0, 0, w, h * 0.16); g.fillRect(0, h * 0.9, w, h * 0.1); finePrint(g, w * 0.1, h * 0.3, w * 0.8, 10, { h: 7, gap: 12, seed: 19 }); });
      const box = at(yaw(carton({ w: 3.4, h: 7.4, d: 3.0, front, side }), 18), -2.2, 0, -1.6);
      return group([box, v]);
    },
  },

  antibiotics: {
    view: V(30, 24),
    build: () => {
      const lab = drugLabel({ name: 'CEFAZOLIN', strength: '1 g  ·  POWDER', sub: 'FOR INJECTION  ·  RECONSTITUTE BEFORE USE', band: '#e07a12', bandText: 'ANTIBIOTIC', window: 1, seed: 16 });
      return vial({ r: 1.55, h: 5.8, cap: 0xe8821c, label: lab, theta: deg(30), powder: true, labelY0: 0.22, labelY1: 0.56 });
    },
  },

  /* ───────────── orthopedic ───────────── */
  splint: { view: V(28, 34), build: ({ loadGLB }) => loadGLB('nz_amb_splint_arm') },
  cervical_collar: { view: V(30, 26), build: ({ loadGLB }) => loadGLB('nz_amb_collar') },
  pelvic_binder: { view: V(30, 30), build: ({ loadGLB }) => loadGLB('nz_amb_binder_worn') },

  plaster_cast: {
    view: V(0, 34),
    build: () => {
      // forearm cast shell: elliptical tapered tube, stockinette cuffs, thumb opening
      const L = 24, seg = 64;
      const outer = new THREE.CylinderGeometry(1, 1, L, seg, 40, true);
      const shape = (g, k) => bend(g, v => {
        const t = (v.y + L / 2) / L;                      // 0 = hand, 1 = elbow
        const R = (2.3 + t * 1.6 + Math.sin(t * Math.PI) * 0.35) * k;
        const a = Math.atan2(v.z, v.x);
        v.x = Math.cos(a) * R * 1.0; v.z = Math.sin(a) * R * 0.78;
        v.y = v.y;
        // slight bend at the wrist
        v.x += Math.pow(1 - t, 2) * 0.8;
      });
      shape(outer, 1);
      const inner = shape(new THREE.CylinderGeometry(1, 1, L - 0.01, seg, 40, true), 0.86);
      const plaster = mat.matte(0xf3f1ea, { roughness: 0.95, normalMap: NT.plaster([3, 6]), normalScale: new THREE.Vector2(1.2, 1.2) });
      const sock = mat.fabric(0xe7e3d8, { normalMap: NT.weave([12, 4]) });
      const parts = [mesh(outer, plaster), mesh(inner, mat.matte(0xd8d4c8, { side: THREE.BackSide, roughness: 1 }))];
      // stockinette roll at both ends
      for (const [y, k] of [[-L / 2, 2.3], [L / 2, 3.9]]) {
        const tg = new THREE.TorusGeometry(1, 0.32, 12, 64);
        const t = mesh(tg, sock); t.rotation.x = Math.PI / 2; t.position.y = y; t.scale.set(k * 0.93, k * 0.73, 1);
        if (y < 0) t.position.x = 0.8;
        parts.push(t);
      }
      // wrap lines (bandage turns) as subtle ridges
      for (let i = 1; i < 6; i++) {
        const t = i / 6, y = -L / 2 + t * L, R = 2.3 + t * 1.6 + Math.sin(t * Math.PI) * 0.35;
        const r = mesh(new THREE.TorusGeometry(1, 0.035, 6, 64), plaster); r.rotation.set(Math.PI / 2 + 0.18, 0, 0); r.position.set(Math.pow(1 - t, 2) * 0.8, y, 0); r.scale.set(R * 1.01, R * 0.79, 1);
        parts.push(r);
      }
      // thumb hole near the hand end + marker doodles (casts get signed)
      parts.push(mesh(new THREE.CircleGeometry(0.75, 32).scale(1, 1.3, 1), mat.matte(0x6e6a62, { roughness: 1 }), { pos: [3.3, -L / 2 + 3.0, 0.4], rot: [0, Math.PI / 2, 0] }));
      parts.push(mesh(new THREE.TorusGeometry(0.75, 0.16, 10, 40).scale(1, 1.3, 1), sock, { pos: [3.32, -L / 2 + 3.0, 0.4], rot: [0, Math.PI / 2, 0] }));
      const ink = canvasTex(1024, 512, (g, w, h) => {
        g.clearRect(0, 0, w, h);
        g.strokeStyle = '#1f5fbf'; g.lineWidth = 9; g.lineCap = 'round';
        g.font = 'italic 700 86px "Lexend", sans-serif'; g.fillStyle = '#1f5fbf'; g.fillText('get well', w * 0.12, h * 0.42);
        g.fillStyle = '#d23a3a'; g.beginPath(); g.moveTo(w * 0.78, h * 0.62); g.bezierCurveTo(w * 0.7, h * 0.48, w * 0.7, h * 0.32, w * 0.78, h * 0.4); g.bezierCurveTo(w * 0.86, h * 0.32, w * 0.86, h * 0.48, w * 0.78, h * 0.62); g.fill();
        g.strokeStyle = '#16191d'; g.lineWidth = 7; g.beginPath(); g.moveTo(w * 0.14, h * 0.72); g.bezierCurveTo(w * 0.25, h * 0.6, w * 0.3, h * 0.85, w * 0.42, h * 0.7); g.bezierCurveTo(w * 0.5, h * 0.6, w * 0.55, h * 0.8, w * 0.62, h * 0.7); g.stroke();
      });
      const inkM = new THREE.MeshStandardMaterial({ map: ink, transparent: true, depthWrite: false, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -3 });
      const band = new THREE.CylinderGeometry(1, 1, 8, 64, 8, true, -0.35 * Math.PI, 0.9 * Math.PI);
      band.translate(0, 2, 0); shape(band, 1.006);
      parts.push(mesh(band, inkM, { order: 3 }));
      const g = group(parts);
      g.rotation.z = Math.PI / 2;                      // lie along X
      return yaw(group([g]), 40);
    },
  },

  crutches: {
    view: V(0, 36, { fill: 0.84 }),
    build: async ({ loadGLB }) => {
      const a = await loadGLB('nz_amb_crutch'), b = await loadGLB('nz_amb_crutch');
      // lay both down side by side
      const lay = (o, z, r) => { const g = group([o]); g.rotation.set(0, 0, Math.PI / 2); const h = group([g]); h.rotation.y = r; h.position.z = z; return h; };
      return yaw(group([lay(a, -3, 0), lay(b, 3, 0.05)]), 38);
    },
  },

  /* ───────────── airway & chest ───────────── */
  bvm: { view: V(34, 30), build: ({ loadGLB }) => loadGLB('nz_amb_bvm') },
  oxygen_mask: {
    view: V(18, 26),
    build: () => {
      const parts = [];
      // dome (x lateral, y depth towards the camera, z nose→chin) mapped to world (x, z→up, y→towards camera)
      const toWorld = v => { const x = v.x, y = v.y, z = v.z; v.set(x, z, y); };
      const dome = new THREE.SphereGeometry(1, 64, 32, 0, TAU, 0, Math.PI / 2);
      bend(dome, v => { const up = Math.max(0, v.z); const k = 0.66 + 0.34 * (1 - up); v.x *= 4.4 * k; v.z *= 5.6; v.y *= 3.8 * (1 - up * 0.25); toWorld(v); });
      const shell = mesh(dome, clearMat({ color: 0x1c3326, spec: 0xd8f5e4, roughness: 0.06, opacity: 0.08, lum: 0.85, envMapIntensity: 1.5 }), { order: 4 });
      const rimG = bend(new THREE.TorusGeometry(1, 0.13, 10, 96).rotateX(Math.PI / 2), v => { const up = Math.max(0, v.z); const k = 0.66 + 0.34 * (1 - up); v.x *= 4.4 * k; v.z *= 5.6; toWorld(v); });
      const rim = mesh(rimG, clearMat({ color: 0xbfe6cf, roughness: 0.2, opacity: 0.5, lum: 0.55 }), { order: 4 });
      const mask = group([shell, rim]);
      mask.add(mesh(rbox(2.0, 0.6, 0.08, 0.03, 1), mat.alu(), { pos: [0, 4.6, 2.2], rot: [-0.6, 0, 0] }));
      for (const sx of [-1, 1]) mask.add(mesh(rcyl(0.85, 0.35, 0.1), mat.plastic(0x2fa36a, { roughness: 0.35 }), { pos: [sx * 3.05, 0.3, 2.0], rot: [0, -sx * 0.5, -sx * Math.PI / 2, 'YXZ'] }));
      mask.add(mesh(rcyl(0.85, 1.6, 0.15), mat.plastic(0x2fa36a, { roughness: 0.35 }), { pos: [0, -5.6, 1.6], rot: [Math.PI, 0, 0] }));
      // strap
      mask.add(mesh(tube([V3(-4.2, 0.5, 0), V3(-6, 0, -3), V3(0, -0.2, -6.5), V3(6, 0, -3), V3(4.2, 0.5, 0)], 0.12, { radial: 8 }), mat.matte(0x2fa36a)));
      mask.rotation.x = deg(-22); mask.position.set(0, 7.0, -2.5);
      parts.push(mask);
      // reservoir bag below the chin, lying forward
      const [bf, bb] = pillow(7, 9, 2.8, { seam: 0.35, nx: 40, ny: 48, power: 0.6 });
      const bm = clearMat({ color: 0x48b47a, roughness: 0.28, opacity: 0.55, lum: 0.5 });
      const bag = group([mesh(bf, bm, { order: 3 }), mesh(bb, bm, { order: 3 })]);
      bag.rotation.set(-Math.PI / 2 + 0.25, 0, deg(6)); bag.position.set(0.3, 1.7, 3.2);
      parts.push(bag);
      // oxygen tubing coiling off to the side
      const tp = [V3(0.2, 1.2, 7.6), V3(2.5, 0.4, 9.2), V3(7, 0.4, 8.5), V3(9.4, 0.4, 4.5), V3(8, 0.4, 0.8), V3(5.6, 0.4, 1.8), V3(6.6, 0.4, 5.2), V3(11, 0.4, 6.4)];
      parts.push(mesh(tube(tp, 0.34, { radial: 14 }), clearMat({ color: 0x5cc88a, roughness: 0.2, opacity: 0.6, lum: 0.55, normalMap: NT.ribs([60, 1]), normalScale: 0.3 }), { order: 4 }));
      return yaw(group(parts), -6);
    },
  },

  intubation_kit: {
    view: V(20, 32),
    build: async ({ loadGLB }) => {
      const ls = await loadGLB('nz_amb_laryngoscope');
      const scope = group([ls]); scope.rotation.set(0, deg(-30), 0); scope.position.set(-2.5, 0, -1.5);
      const t = at(yaw(ett({ len: 17 }), -40), 0.5, 0, 3.0);
      const s = at(yaw(syringe({ len: 6.5, r: 0.7, ml: 10, fill: 0, cap: 0xf1f1f1 }), 70), 6.4, 0.75, -0.8);
      return group([scope, t, s]);
    },
  },

  chest_drain_kit: {
    view: V(20, 40),
    build: () => {
      const paper = canvasTex(1024, 1024, (g, w, h) => { g.fillStyle = '#f3f2ec'; g.fillRect(0, 0, w, h); g.fillStyle = '#2b5fae'; g.fillRect(0, 0, w, h * 0.12); txt(g, 'CHEST DRAIN', w * 0.05, h * 0.085, { size: 66, weight: 800, color: '#fff' }); txt(g, '28 Fr  ·  WITH TROCAR  ·  STERILE', w * 0.05, h * 0.95, { size: 40, weight: 700, color: '#333' }); barcode(g, w * 0.66, h * 0.88, w * 0.28, h * 0.08, 101); });
      // coiled chest tube with the radiopaque stripe + side eyes, connector, curved clamp beside
      const pts = [];
      for (let i = 0; i <= 120; i++) { const a = i / 120 * TAU * 1.25; const r = 5.4 - i / 120 * 1.6; pts.push(V3(Math.cos(a) * r, 0.75, Math.sin(a) * r * 1.25)); }
      const cv = new THREE.CatmullRomCurve3(pts);
      const tubeM = mesh(new THREE.TubeGeometry(cv, 240, 0.6, 24, false), clearMat({ color: 0xe9f3f7, roughness: 0.15, opacity: 0.6, lum: 0.8 }), { order: 7 });
      const line = mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts.map(p => p.clone().add(V3(0, 0.55, 0)))), 240, 0.08, 6, false), mat.plastic(0x2f6fd8, { roughness: 0.4 }));
      const conn = mesh(lathe([[0.4, 0], [0.62, 0.3], [0.62, 2], [0.4, 2.6]], { seg: 32 }), mat.plastic(0xf4f4f2));
      const e = cv.getPointAt(1), d = cv.getTangentAt(1); conn.position.copy(e); conn.quaternion.setFromUnitVectors(V3(0, 1, 0), d);
      const contents = group([tubeM, line, conn]);
      const pouch = peelPouch({ w: 15, h: 17, paper, contents, bulge: 1.0 });
      const clamp = at(yaw(hemostat({ len: 14, curved: true, open: 0.1 }), -20), 2, 0.12, 11.5);
      return yaw(group([pouch, clamp]), -6);
    },
  },

  decompression_needle: {
    view: V(0, 32),
    build: () => {
      const n = ivCannula({ gauge: 14, len: 8 });
      n.scale.setScalar(1.3);
      // protective sheath lying beside
      const sh = mesh(lathe([[0.3, 0], [0.26, 1], [0.2, 8.5], [0.12, 9.2], [0.001, 9.25]], { seg: 32 }), clearMat({ color: 0xf6fbff, roughness: 0.1, opacity: 0.3, lum: 0.75 }), { order: 4, rot: [0, 0, -Math.PI / 2], pos: [-1, 0.32, 3.2] });
      const tag = decal(3.6, 1.0, canvasTex(512, 140, (g, w, h) => { g.fillStyle = '#e8742a'; rr(g, 0, 0, w, h, 20); g.fill(); txt(g, '14 G  ·  83 mm', w / 2, h * 0.68, { size: 66, weight: 800, color: '#fff', align: 'center' }); }), { pos: [-3.6, 0.03, -3.2], rot: [-Math.PI / 2, 0, 0] });
      return yaw(group([n, sh, tag]), 36);
    },
  },

  /* ───────────── angiography ───────────── */
  angio_kit: {
    view: V(18, 40),
    build: () => {
      // guide-wire hoop dispenser + sheath introducer with side port + stopcock
      const hoopM = mat.plastic(0x2f86d8, { roughness: 0.3, clearcoat: 0.5 });
      const parts = [];
      for (let k = 0; k < 3; k++) { const t = mesh(new THREE.TorusGeometry(6.2 - k * 0.42, 0.22, 12, 120), hoopM); t.rotation.x = Math.PI / 2; t.position.y = 0.22; parts.push(t); }
      for (let k = 0; k < 4; k++) parts.push(mesh(rbox(0.8, 0.7, 1.6, 0.15, 2), mat.plastic(0xf2f2ef), { pos: [Math.cos(k * 1.6) * 5.8, 0.35, Math.sin(k * 1.6) * 5.8], rot: [0, -k * 1.6, 0] }));
      // J-tip straightener at the hoop end
      parts.push(mesh(rcyl(0.3, 1.8, 0.1), mat.plastic(0xf2f2ef), { pos: [6.3, 0.3, 0.6], rot: [Math.PI / 2, 0, 0] }));
      // sheath: hub with valve + side tube + 3-way stopcock, dilator through it
      const sheath = group([
        mesh(lathe([[0.001, 0], [0.75, 0], [0.8, 0.2], [0.8, 1.8], [0.5, 2.4], [0.25, 2.8], [0.001, 2.8]], { seg: 40 }), mat.plastic(0xf4f4f2, { roughness: 0.3 }), { rot: [0, 0, -Math.PI / 2], pos: [-2, 0, 0] }),
        mesh(rcyl(0.7, 0.5, 0.15), mat.rubber(0x2b2f33), { rot: [0, 0, -Math.PI / 2], pos: [-2.4, 0, 0] }),
        mesh(cyl(0.18, 10, { seg: 16 }), clearMat({ color: 0xeef6fa, opacity: 0.55, roughness: 0.15 }), { rot: [0, 0, -Math.PI / 2], pos: [0.8, 0, 0], order: 3 }),
        mesh(cyl(0.11, 13, { seg: 12 }), mat.plastic(0x7fbde8, { roughness: 0.3 }), { rot: [0, 0, -Math.PI / 2], pos: [-3.4, 0, 0] }),
        mesh(tube([V3(-1.2, 0, 0.5), V3(-1.4, 0, 2), V3(-2.8, 0, 3.6), V3(-5, 0, 4.2)], 0.14, { radial: 10 }), clearMat({ color: 0xeef6fa, opacity: 0.5, roughness: 0.15 }), { order: 3 }),
        mesh(rbox(1.0, 0.8, 1.0, 0.2, 2), mat.plastic(0x2f86d8), { pos: [-5.5, 0, 4.25] }),
        mesh(rbox(0.3, 0.3, 2.2, 0.1, 2), mat.plastic(0xf4f4f2), { pos: [-5.5, 0.5, 4.25] }),
      ]);
      sheath.position.set(0, 0.85, 1); sheath.rotation.y = deg(18);
      parts.push(sheath);
      return yaw(group(parts), 0);
    },
  },

  contrast_dye: { view: V(30, 24), build: () => contrastBottle({ theta: deg(30) }) },

  embolization_coil: {
    view: V(20, 40),
    build: () => {
      const cardTex = canvasTex(1024, 640, (g, w, h) => { g.fillStyle = '#1d2d44'; g.fillRect(0, 0, w, h); g.fillStyle = '#2f86d8'; g.fillRect(0, 0, w, h * 0.14); txt(g, 'EMBOLIZATION COIL', w * 0.05, h * 0.1, { size: 54, weight: 800, color: '#fff' }); txt(g, '6 mm x 20 cm  ·  PLATINUM', w * 0.05, h * 0.93, { size: 40, weight: 700, color: '#cfe0f2' }); finePrint(g, w * 0.62, h * 0.84, w * 0.34, 3, { h: 7, gap: 9, seed: 111, color: 'rgba(255,255,255,.4)' }); });
      const c = mesh(rbox(14, 0.2, 9, 0.1, 2), [mat.matte(0x1d2d44), mat.matte(0x1d2d44), mat.printed(cardTex, { roughness: 0.5 }), mat.matte(0x1d2d44), mat.matte(0x1d2d44), mat.matte(0x1d2d44)], { pos: [0, 0.1, 0] });
      const coil = at(emboCoil({ wire: true }), -3.2, 0.2, -1.2);
      coil.scale.setScalar(1.6);
      return yaw(group([c, coil]), -6);
    },
  },

  /* ───────────── equipment ───────────── */
  stethoscope: { view: V(20, 44), build: ({ loadGLB }) => loadGLB('nz_amb_stethoscope') },
  defibrillator: { view: V(32, 26), build: ({ loadGLB }) => loadGLB('nz_amb_defib') },
  trauma_kit: { view: V(30, 30), build: ({ loadGLB }) => loadGLB('nz_amb_kitcase_closed') },
  ems_pager: { view: V(28, 26), build: ({ loadGLB }) => loadGLB('nz_amb_pager') },

  medbag: {
    view: V(32, 22),
    build: () => {
      const W = 34, H = 26, D = 22;
      const red = mat.fabric(0xb0202a, { normalMap: NT.weave([14, 10]), normalScale: new THREE.Vector2(0.7, 0.7) });
      const black = mat.fabric(0x22252a, { normalMap: NT.weave([14, 6]) });
      const refl = new THREE.MeshPhysicalMaterial({ color: 0xc9ced3, roughness: 0.35, metalness: 0.4, normalMap: NT.grain([10, 2]), normalScale: new THREE.Vector2(0.3, 0.3), clearcoat: 0.6 });
      const parts = [mesh(rbox(W, H, D, 3.2, 6), red, { pos: [0, H / 2 + 2.4, 0] })];
      parts.push(mesh(rbox(W + 0.3, 4.2, D + 0.3, 1.6, 4), black, { pos: [0, 2.5, 0] }));
      // black piping on the vertical edges + lid zip all round
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) parts.push(mesh(cyl(0.45, H - 3, { seg: 12, y: 4.4 }), black, { pos: [sx * (W / 2 - 1.0), 0, sz * (D / 2 - 1.0)] }));
      const zipPath = [];
      for (let i = 0; i <= 64; i++) { const a = i / 64 * TAU; const cx = Math.cos(a), cz = Math.sin(a); const sx = Math.sign(cx) * Math.pow(Math.abs(cx), 0.25), sz = Math.sign(cz) * Math.pow(Math.abs(cz), 0.25); zipPath.push(V3(sx * (W / 2 + 0.05), H * 0.86 + 2.4, sz * (D / 2 + 0.05))); }
      parts.push(mesh(strap(zipPath, 0.9, 0.25, { up: V3(0, 1, 0), closed: true }), mat.matte(0x15171a, { normalMap: NT.ribs([120, 1]) })));
      // front pocket with its own zip
      parts.push(mesh(rbox(W * 0.74, H * 0.52, 4, 1.6, 4), red, { pos: [0, H * 0.32 + 2.4, D / 2 + 0.6] }));
      parts.push(mesh(rbox(W * 0.66, 0.25, 0.8, 0.1, 1), mat.matte(0x15171a), { pos: [0, H * 0.57 + 2.4, D / 2 + 2.3] }));
      parts.push(mesh(rbox(1.4, 2.2, 0.35, 0.15, 2), black, { pos: [W * 0.28, H * 0.53 + 2.4, D / 2 + 2.75] }));
      // reflective bands around the bag
      parts.push(mesh(rbox(W + 0.25, 1.6, D + 0.25, 3, 4), refl, { pos: [0, H * 0.7 + 2.4, 0] }));
      // zip on the lid + pull tabs
      parts.push(mesh(rbox(W - 6, 0.25, 0.7, 0.1, 1), mat.matte(0x15171a), { pos: [0, H + 2.42, D * 0.32] }));
      parts.push(mesh(rbox(1.6, 0.4, 0.8, 0.15, 2), mat.steel({ roughness: 0.3 }), { pos: [W * 0.32, H + 2.6, D * 0.32 + 0.5] }));
      // patch with star of life on the front
      const patch = canvasTex(512, 512, (g, w) => { g.fillStyle = '#f3f4f2'; g.beginPath(); g.arc(w / 2, w / 2, w / 2, 0, TAU); g.fill(); starOfLife(g, w / 2, w / 2, w * 0.36, '#1f5fbf'); });
      parts.push(decal(7.5, 7.5, patch, { pos: [-W * 0.16, H * 0.32 + 2.4, D / 2 + 2.62] }));
      // top grab handle
      parts.push(mesh(strap([V3(-6, H + 2.3, -2), V3(-5, H + 5.4, -2), V3(5, H + 5.4, -2), V3(6, H + 2.3, -2)], 3, 0.7, { up: V3(0, 0, 1) }), black));
      // telescopic handle at the back + wheels
      for (const s of [-1, 1]) {
        parts.push(mesh(cyl(0.6, 12, { y: H + 2 }), mat.alu(0xb9bfc5, { roughness: 0.25 }), { pos: [s * 9, 0, -D / 2 + 1.1] }));
        parts.push(mesh(cyl(0.5, 4, { y: H + 13.8 }), mat.alu(0xd0d5da, { roughness: 0.2 }), { pos: [s * 9, 0, -D / 2 + 1.1] }));
        const wh = group([mesh(new THREE.CylinderGeometry(3.0, 3.0, 2.4, 40).rotateZ(Math.PI / 2), mat.rubber(0x1c1e21)), mesh(new THREE.CylinderGeometry(1.6, 1.6, 2.5, 30).rotateZ(Math.PI / 2), mat.plastic(0x3a3e44))]);
        wh.position.set(s * (W / 2 - 3.5), 3.0, -D / 2 + 2.2);
        parts.push(wh);
      }
      parts.push(mesh(rbox(20, 2.2, 2.4, 1.0, 3), mat.rubber(0x1f2226, { roughness: 0.6 }), { pos: [0, H + 17.6, -D / 2 + 1.1] }));
      return group(parts);
    },
  },

  wheelchair: {
    view: V(38, 18, { fill: 0.84 }),
    build: () => {
      const frame = mat.alu(0x9aa1a8, { roughness: 0.28 });
      const black = mat.rubber(0x1d1f22, { roughness: 0.6 });
      const sling = mat.fabric(0x22262b, { normalMap: NT.weave([10, 10]) });
      const parts = [];
      const T = (pts, r = 0.9) => mesh(tube(pts, r, { radial: 14, tension: 0.3 }), frame);
      const W = 22; // half seat width
      for (const s of [-1, 1]) {
        const x = s * W;
        // side frame: rear upright with push handle, seat rail, front down tube, footrest
        parts.push(T([V3(x, 46, -18), V3(x, 88, -21), V3(x, 92, -24), V3(x, 93, -30)]));
        parts.push(T([V3(x, 48, -18), V3(x, 48, 16), V3(x, 44, 22), V3(x, 14, 30), V3(x, 9, 34)]));
        parts.push(T([V3(x, 24, -16), V3(x, 24, 18)], 0.75));
        parts.push(T([V3(x, 48, -18), V3(x, 24, -16)], 0.75));
        // armrest
        parts.push(mesh(rbox(4, 2.2, 26, 1, 3), black, { pos: [x, 68, -2] }));
        parts.push(T([V3(x, 48, 8), V3(x, 67, 8)], 0.7));
        // push handle grip
        parts.push(mesh(cyl(1.4, 11, { seg: 20 }), black, { pos: [x, 93, -25], rot: [Math.PI / 2, 0, 0] }));
        // footplate
        parts.push(mesh(rbox(14, 1.2, 10, 0.5, 2), black, { pos: [x - s * 6, 9, 36] }));
        // big rear wheel: tyre, rim, push rim, spokes, hub
        const wx = x + s * 4.5;
        const wheel = group([], { pos: [wx, 30, -12] });
        wheel.add(mesh(new THREE.TorusGeometry(28.5, 1.5, 16, 96).rotateY(Math.PI / 2), black));
        wheel.add(mesh(new THREE.TorusGeometry(26.8, 0.6, 10, 96).rotateY(Math.PI / 2), mat.alu(0xc9ced3, { roughness: 0.2 })));
        const pr = mesh(new THREE.TorusGeometry(25.5, 0.55, 10, 96).rotateY(Math.PI / 2), mat.chrome());
        pr.position.x = s * 3.2; wheel.add(pr);
        for (let k = 0; k < 6; k++) { const a = k / 6 * TAU; wheel.add(mesh(cyl(0.3, 3.2, { seg: 8 }), mat.chrome(), { pos: [0, Math.cos(a) * 25.5, Math.sin(a) * 25.5], rot: [0, 0, -s * Math.PI / 2] })); }
        for (let k = 0; k < 24; k++) { const a = k / 24 * TAU; wheel.add(mesh(cyl(0.13, 26.4, { seg: 6 }), mat.steel(), { pos: [s * (k % 2 ? 0.9 : -0.9), 0, 0], rot: [a, 0, 0] })); }
        wheel.add(mesh(new THREE.CylinderGeometry(2.4, 2.4, 4, 24).rotateZ(Math.PI / 2), mat.alu(0x8d939a)));
        parts.push(wheel);
        // front caster
        const cs = group([], { pos: [x, 7.2, 24] });
        cs.add(mesh(new THREE.CylinderGeometry(7.2, 7.2, 2.6, 32).rotateZ(Math.PI / 2), black));
        cs.add(mesh(new THREE.CylinderGeometry(4, 4, 2.7, 24).rotateZ(Math.PI / 2), mat.plastic(0x3a3e44)));
        cs.add(mesh(rbox(3.6, 9, 2, 0.5, 2), frame, { pos: [0, 5, -2] }));
        parts.push(cs);
      }
      // cross braces, seat + back sling
      parts.push(T([V3(-W, 24, -2), V3(W, 46, 4)], 0.7), T([V3(W, 24, -2), V3(-W, 46, 4)], 0.7));
      parts.push(mesh(rbox(W * 2 - 1, 1.6, 36, 0.7, 3), sling, { pos: [0, 49, -1] }));
      parts.push(mesh(rbox(W * 2 - 1, 36, 1.4, 0.6, 3), sling, { pos: [0, 68, -20], rot: [-0.08, 0, 0] }));
      parts.push(mesh(rbox(W * 2 - 1, 4, 3, 1.2, 3), sling, { pos: [0, 49, 17] }));
      return group(parts);
    },
  },

  bodybag: {
    view: V(25, 36),
    build: () => {
      const L = 34, Wd = 16, T = 5.2;
      const [f, b] = pillow(Wd, L, T, { seam: 0.9, nx: 48, ny: 80, power: 0.45, ramp: 2.4 });
      const cloth = new THREE.MeshPhysicalMaterial({ color: 0x23262b, roughness: 0.48, clearcoat: 0.4, clearcoatRoughness: 0.35, normalMap: NT.grain([6, 10]), normalScale: new THREE.Vector2(0.4, 0.4) });
      const bag = group([mesh(f, cloth), mesh(b, cloth)]);
      bag.rotation.x = -Math.PI / 2; bag.position.y = T / 2;
      const parts = [bag];
      // U-shaped zip on top
      const zp = [];
      const zx = Wd / 2 - 2.4, zz = L / 2 - 2.6;
      const top = (x, z) => {
        const ix = Math.max(0, 1 - Math.abs(x) / (Wd / 2 - 0.9)), iz = Math.max(0, 1 - Math.abs(z) / (L / 2 - 0.9));
        return T / 2 + Math.pow(Math.min(1, ix * 2.4) * Math.min(1, iz * 2.4), 0.45) * (T / 2) + 0.05;
      };
      for (let i = 0; i <= 60; i++) { const z = zz - i / 60 * (2 * zz - 3); zp.push(V3(-zx, top(-zx, z), z)); }
      for (let i = 0; i <= 20; i++) { const a = Math.PI + i / 20 * Math.PI; const x = Math.cos(a) * zx, z = -zz + 3 + Math.sin(a) * 3; zp.push(V3(x, top(x, z), z)); }
      for (let i = 0; i <= 60; i++) { const z = -zz + 3 + i / 60 * (2 * zz - 3); zp.push(V3(zx, top(zx, z), z)); }
      parts.push(mesh(strap(zp, 1.6, 0.1, { up: V3(0, 1, 0), steps: 400 }), mat.matte(0x101113, { roughness: 0.8 })));
      parts.push(mesh(strap(zp.map(p => p.clone().add(V3(0, 0.08, 0))), 0.55, 0.16, { up: V3(0, 1, 0), steps: 400 }), mat.satin({ roughness: 0.3, normalMap: NT.ribs([90, 1]), normalScale: new THREE.Vector2(1.2, 1.2) })));
      for (const zz2 of [6, 3.4]) parts.push(mesh(rbox(1.3, 0.45, 2.6, 0.25, 2), mat.steel({ roughness: 0.25 }), { pos: [zx + 0.4, top(zx, zz2) + 0.25, zz2], rot: [0, 0.25, 0] }));
      // carry handles on the sides
      for (const s of [-1, 1]) for (const z of [-8, 0, 8]) parts.push(mesh(strap([V3(s * (Wd / 2 - 0.2), T * 0.55, z - 2.2), V3(s * (Wd / 2 + 1.4), T * 0.5, z - 1.4), V3(s * (Wd / 2 + 1.4), T * 0.5, z + 1.4), V3(s * (Wd / 2 - 0.2), T * 0.55, z + 2.2)], 1.4, 0.3, { up: V3(0, 1, 0) }), mat.fabric(0x15171a)));
      // ID tag
      const tag = canvasTex(400, 220, (g, w, h) => { g.fillStyle = '#f2f1ea'; rr(g, 0, 0, w, h, 16); g.fill(); g.fillStyle = '#c4122f'; g.fillRect(0, 0, w, h * 0.24); txt(g, 'IDENTIFICATION', w * 0.06, h * 0.17, { size: 30, weight: 800, color: '#fff' }); finePrint(g, w * 0.06, h * 0.38, w * 0.8, 4, { h: 9, gap: 14, seed: 121 }); });
      parts.push(decal(4.6, 2.6, tag, { pos: [0, top(0, -9) + 0.05, -9], rot: [-Math.PI / 2 + 0.05, 0, 0] }));
      return yaw(group(parts), -24);
    },
  },

  /* ───────────── documents ───────────── */
  xray_film: {
    view: V(18, 44),
    build: () => {
      const f = xrayFilm({ w: 14, d: 17 });
      // a slight curl so it reads as a film sheet
      f.children[0].geometry = bend(f.children[0].geometry.clone(), v => { v.y += Math.pow(Math.max(0, v.x / 7), 2) * 0.9; });
      return yaw(f, -10);
    },
  },

  triage_ticket: {
    view: V(12, 46),
    build: () => {
      const tex = canvasTex(640, 1100, (g, w, h) => {
        g.fillStyle = '#fbfbf6'; g.fillRect(0, 0, w, h);
        g.fillStyle = TEAL; g.fillRect(0, 0, w, h * 0.12);
        txt(g, 'QUEUE PASS', w / 2, h * 0.085, { size: 62, weight: 800, color: '#fff', align: 'center' });
        txt(g, 'YOUR NUMBER', w / 2, h * 0.21, { size: 36, weight: 600, color: '#444', align: 'center' });
        txt(g, 'A042', w / 2, h * 0.42, { size: 200, weight: 800, color: '#14181c', align: 'center', font: '"Lexend", sans-serif' });
        g.fillStyle = '#14181c'; g.fillRect(w * 0.1, h * 0.47, w * 0.8, 4);
        txt(g, 'EMERGENCY DEPT.  ·  WAITING AREA', w / 2, h * 0.53, { size: 30, weight: 600, color: '#333', align: 'center' });
        txt(g, '19 OCT  14:32', w / 2, h * 0.59, { size: 34, weight: 500, color: '#333', align: 'center', font: '"JetBrains Mono", monospace' });
        txt(g, 'PLEASE WAIT TO BE CALLED', w / 2, h * 0.67, { size: 30, weight: 700, color: TEAL, align: 'center' });
        barcode(g, w * 0.15, h * 0.74, w * 0.7, h * 0.11, 131);
        finePrint(g, w * 0.15, h * 0.9, w * 0.7, 2, { h: 8, gap: 10, seed: 132 });
      });
      const W = 6.4, D = 11;
      const s = new THREE.Shape();
      s.moveTo(-W / 2, -D / 2); s.lineTo(W / 2, -D / 2);
      for (let i = 0; i <= 16; i++) s.lineTo(W / 2 - i * W / 16, D / 2 - (i % 2 ? 0.25 : 0));   // torn top edge
      s.lineTo(-W / 2, -D / 2);
      const geo = bend(extrude(s, 0.03, { bevel: 0.0, curveSeg: 4 }), v => { v.z += Math.pow(Math.max(0, -v.y / (D / 2)), 2) * 0.9 + Math.pow(Math.max(0, v.y / (D / 2)), 2) * 0.5; });
      const m = mesh(geo, [mat.paper(tex, { roughness: 0.6 }), mat.matte(0xf3f3ee)]);
      m.rotation.x = -Math.PI / 2;
      return yaw(group([m]), -12);
    },
  },

  insurance_card: {
    view: V(14, 52),
    build: () => {
      const tex = canvasTex(1012, 638, (g, w, h) => {
        const gr = g.createLinearGradient(0, 0, w, h); gr.addColorStop(0, '#0e9a92'); gr.addColorStop(1, '#0a5d74');
        g.fillStyle = gr; rr(g, 0, 0, w, h, 40); g.fill();
        g.fillStyle = 'rgba(255,255,255,.08)'; g.beginPath(); g.arc(w * 0.95, h * 0.1, h * 0.7, 0, TAU); g.fill();
        g.fillStyle = 'rgba(255,255,255,.06)'; g.beginPath(); g.arc(w * 0.9, h * 1.0, h * 0.5, 0, TAU); g.fill();
        cross(g, w * 0.1, h * 0.17, h * 0.15, '#ffffff');
        txt(g, 'HEALTH INSURANCE', w * 0.17, h * 0.2, { size: 52, weight: 800, color: '#fff' });
        txt(g, 'MEMBER CARD', w * 0.17, h * 0.28, { size: 28, weight: 600, color: 'rgba(255,255,255,.8)', spacing: 4 });
        // chip
        const cg = g.createLinearGradient(0, h * 0.38, 0, h * 0.58); cg.addColorStop(0, '#f4dc9a'); cg.addColorStop(1, '#c79a45');
        g.fillStyle = cg; rr(g, w * 0.08, h * 0.38, w * 0.13, h * 0.19, 14); g.fill();
        g.strokeStyle = 'rgba(90,60,10,.6)'; g.lineWidth = 3; g.beginPath(); g.moveTo(w * 0.08, h * 0.475); g.lineTo(w * 0.21, h * 0.475); g.moveTo(w * 0.145, h * 0.38); g.lineTo(w * 0.145, h * 0.57); g.stroke();
        txt(g, '8034  2216  0957  41', w * 0.08, h * 0.72, { size: 58, weight: 500, color: '#fff', font: '"JetBrains Mono", monospace' });
        txt(g, 'MEMBER', w * 0.08, h * 0.83, { size: 22, weight: 600, color: 'rgba(255,255,255,.7)' });
        txt(g, 'J. DOE', w * 0.08, h * 0.91, { size: 38, weight: 700, color: '#fff' });
        txt(g, 'VALID 10/29', w * 0.62, h * 0.91, { size: 34, weight: 600, color: '#fff' });
      });
      const c1 = card({ front: tex });
      c1.scale.setScalar(1.4);
      return yaw(c1, -16);
    },
  },

  /* ───────────── fallback ───────────── */
  nza_unknown: {
    view: V(32, 28),
    build: () => {
      const q = canvasTex(1024, 1024, (g, w, h) => {
        g.fillStyle = '#ecebe6'; g.fillRect(0, 0, w, h);
        g.fillStyle = '#5c646c'; g.fillRect(0, h * 0.86, w, h * 0.14);
        txt(g, '?', w / 2, h * 0.7, { size: 640, weight: 800, color: '#59626b', align: 'center' });
        txt(g, 'MEDICAL SUPPLY', w / 2, h * 0.955, { size: 64, weight: 700, color: '#fff', align: 'center', spacing: 4 });
      });
      const top = canvasTex(1024, 1024, (g, w, h) => { g.fillStyle = '#ecebe6'; g.fillRect(0, 0, w, h); g.fillStyle = 'rgba(200,198,190,.9)'; g.fillRect(w * 0.42, 0, w * 0.16, h); txt(g, '?', w / 2, h * 0.68, { size: 480, weight: 800, color: '#7a828a', align: 'center' }); });
      const plain = mat.matte(0xe6e5df, { roughness: 0.7 });
      const fm = mat.printed(q, { roughness: 0.55, clearcoat: 0.15 });
      const box = mesh(rbox(14, 12, 14, 0.35, 3), [fm, fm, mat.printed(top, { roughness: 0.55, clearcoat: 0.15 }), plain, fm, fm], { pos: [0, 6, 0] });
      // tape across the lid
      const tape = mesh(rbox(2.3, 0.05, 14.1, 0.02, 1), clearMat({ color: 0xd9d4bf, roughness: 0.3, opacity: 0.5 }), { pos: [0, 12.02, 0], order: 3 });
      return group([box, tape]);
    },
  },
};
