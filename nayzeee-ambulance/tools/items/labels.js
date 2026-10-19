// Printed labels / packaging artwork (canvas → texture). Generic medical wording only:
// no brand names, no wordmarks, no logos (a plain cross / star of life at most).
import { canvasTex, txt, rr, barcode, datamatrix, finePrint, cross, starOfLife, FONT } from './lib.js';

// pharmaceutical wrap label: name, strength, band colour; w × h px maps onto the wrapped area
export function drugLabel({ w = 1024, h = 300, name, strength, sub = '', band = '#d33', bandText = '', bg = '#fbfbf8', ink = '#14181c', seed = 3, stripes = false, window: win = 0 } = {}) {
  return canvasTex(w, h, (g) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    const x0 = w * 0.06, cw = w * (win ? 0.62 : 0.88);
    // colour band at the top + bottom rule
    g.fillStyle = band; g.fillRect(0, 0, w, h * 0.2);
    if (stripes) { g.save(); g.beginPath(); g.rect(0, 0, w, h * 0.2); g.clip(); g.fillStyle = 'rgba(255,255,255,.85)'; for (let x = -h; x < w; x += h * 0.22) { g.beginPath(); g.moveTo(x, h * 0.2); g.lineTo(x + h * 0.08, h * 0.2); g.lineTo(x + h * 0.28, 0); g.lineTo(x + h * 0.2, 0); g.fill(); } g.restore(); }
    if (bandText) txt(g, bandText, x0, h * 0.15, { size: h * 0.12, weight: 700, color: '#fff', spacing: 2 });
    g.fillStyle = band; g.fillRect(0, h * 0.93, w, h * 0.07);
    txt(g, name, x0, h * 0.47, { size: h * 0.2, weight: 800, color: ink, max: cw });
    txt(g, strength, x0, h * 0.68, { size: h * 0.14, weight: 600, color: band, max: cw });
    if (sub) txt(g, sub, x0, h * 0.82, { size: h * 0.075, weight: 400, color: '#333', max: cw });
    // fine print + barcode on the far side of the wrap
    const fx = x0 + cw + w * 0.03;
    if (win) {
      finePrint(g, fx, h * 0.3, w - fx - w * 0.04, 5, { h: h * 0.025, gap: h * 0.03, seed });
      barcode(g, fx, h * 0.62, w * 0.18, h * 0.2, seed);
    }
  });
}

// box / carton print: front panel artwork
export function boxFront({ w = 1024, h = 640, title, line2 = '', band = '#0c8a83', bg = '#f7f8f6', icon = null, foot = 'STERILE', seed = 4, dark = false } = {}) {
  return canvasTex(w, h, (g) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    g.fillStyle = band; g.fillRect(0, 0, w, h * 0.16); g.fillRect(0, h * 0.9, w, h * 0.1);
    const ink = dark ? '#f2f4f5' : '#15191d';
    txt(g, title, w * 0.07, h * 0.42, { size: h * 0.15, weight: 800, color: ink, max: w * 0.86 });
    if (line2) txt(g, line2, w * 0.07, h * 0.56, { size: h * 0.075, weight: 600, color: dark ? '#cfd8dc' : '#3b4247', max: w * 0.86 });
    if (icon) icon(g, w, h);
    finePrint(g, w * 0.07, h * 0.64, w * 0.5, 3, { h: h * 0.018, gap: h * 0.026, seed, color: dark ? 'rgba(255,255,255,.45)' : 'rgba(0,0,0,.4)' });
    if (foot) txt(g, foot, w * 0.07, h * 0.975, { size: h * 0.06, weight: 700, color: '#fff', spacing: 3 });
    barcode(g, w * 0.7, h * 0.66, w * 0.22, h * 0.15, seed, dark ? '#e8eef0' : '#111');
  });
}

// peel pouch: paper back with a printed header, clear film front is a separate material
export function pouchPaper({ w = 1024, h = 1024, title = '', line2 = '', color = '#1d6fb8', seed = 6 } = {}) {
  return canvasTex(w, h, (g) => {
    g.fillStyle = '#f3f2ec'; g.fillRect(0, 0, w, h);
    // chevron peel edge + printed border
    g.fillStyle = color; g.fillRect(0, 0, w, h * 0.12);
    g.fillStyle = '#f3f2ec';
    for (let x = 0; x < w; x += w / 12) { g.beginPath(); g.moveTo(x, h * 0.12); g.lineTo(x + w / 24, h * 0.07); g.lineTo(x + w / 12, h * 0.12); g.fill(); }
    if (title) txt(g, title, w * 0.07, h * 0.06, { size: h * 0.045, weight: 800, color: '#fff', base: 'middle', max: w * 0.86 });
    if (line2) txt(g, line2, w * 0.07, h * 0.95, { size: h * 0.035, weight: 600, color: '#333', max: w * 0.6 });
    g.strokeStyle = 'rgba(0,0,0,.12)'; g.lineWidth = 3; g.strokeRect(w * 0.03, h * 0.14, w * 0.94, h * 0.84);
    barcode(g, w * 0.68, h * 0.9, w * 0.26, h * 0.07, seed);
  });
}

export { cross, starOfLife, rr, txt, barcode, datamatrix, finePrint, FONT };
