/* ═══════════════════════════════════════════════════════════
   NAYZEEE SNEAKERS · studio keyer
   Turns a screenshot of the shoe in its chroma box into an icon:
   crop the centre square (the on-screen guide), key out the backdrop with
   soft edges + despill, trim to the shoe, centre it on a transparent square.
   Same pipeline as the nayzeee-backpack icon studio. The chroma maths is
   adapted from uz_AutoShot (Apache-2.0, https://github.com/uz-scripts).
   Runs in the NUI so the server never touches a full screenshot.
   ═══════════════════════════════════════════════════════════ */
'use strict';

const Keyer = (() => {
  function load(src) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('screenshot did not load'));
      img.src = src;
    });
  }

  // which channel the backdrop is made of, and the two it dominates
  const KEYS = { green: { p: 1, a: 0, b: 2 }, blue: { p: 2, a: 0, b: 1 } };

  function key(d, mode) {
    for (let i = 0; i < d.length; i += 4) {
      const r = d[i], g = d[i + 1], b = d[i + 2];
      let k = 0;
      if (mode === 'magenta') {
        // red AND blue over green
        const rg = r - g, bg = b - g;
        const minOver = Math.min(rg, bg), primary = Math.min(r, b);
        if (minOver > 0 && primary > 10) {
          const edge = minOver < 20 ? minOver / 20 : 1;
          const soft = primary < 40 ? (primary - 10) / 30 : 1;
          k = Math.min(1, (rg + bg) / (r + b + 1)) * edge * soft;
        }
        if (k > 0) {
          d[i + 3] = (255 * (1 - k) + 0.5) | 0;
          d[i] = (r - rg * k + 0.5) | 0;
          d[i + 2] = (b - bg * k + 0.5) | 0;
        }
      } else {
        const ch = KEYS[mode] || KEYS.green;
        const px = [r, g, b];
        const p = px[ch.p], oa = p - px[ch.a], ob = p - px[ch.b];
        const minOver = Math.min(oa, ob);
        if (minOver > 0 && p > 10) {
          const edge = minOver < 20 ? minOver / 20 : 1;
          const soft = p < 40 ? (p - 10) / 30 : 1;
          k = Math.min(1, (oa + ob) / (p + 1)) * edge * soft;
        }
        if (k > 0) {
          d[i + 3] = (255 * (1 - k) + 0.5) | 0;
          const cap = Math.max(px[ch.a], px[ch.b]);
          d[i + ch.p] = (p - (p - cap) * k + 0.5) | 0;
        }
      }
    }
  }

  // two light passes of a 5x5 box blur on alpha edges only, for smooth cut-outs
  function feather(d, w, h) {
    const R = 2, K = (R * 2 + 1) * (R * 2 + 1);
    const a = new Uint8Array(w * h);
    for (let pass = 0; pass < 2; pass++) {
      for (let i = 0; i < w * h; i++) a[i] = d[(i << 2) + 3];
      for (let y = R; y < h - R; y++) {
        for (let x = R; x < w - R; x++) {
          const idx = y * w + x, v = a[idx];
          if ((v === 0 || v === 255) && a[idx - 1] === v && a[idx + 1] === v && a[idx - w] === v && a[idx + w] === v) continue;
          let s = 0;
          for (let ky = -R; ky <= R; ky++) {
            const row = (y + ky) * w + x;
            for (let kx = -R; kx <= R; kx++) s += a[row + kx];
          }
          d[(idx << 2) + 3] = (s / K + 0.5) | 0;
        }
      }
    }
  }

  function bounds(d, w, h) {
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (d[((y * w + x) << 2) + 3] > 12) {
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
      }
    }
    return x1 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
  }

  async function run(job) {
    const img = await load(job.image);

    // centre square of the screen, the same area the on-screen guide shows
    const side = Math.round(Math.min(img.width, img.height) * 0.8);
    const sx = Math.round((img.width - side) / 2);
    const sy = Math.round((img.height - side) / 2);

    // key at a small working size: the output is 256-512px, so 768 is plenty and stays fast
    const work = Math.min(side, 768);
    const c = document.createElement('canvas');
    c.width = c.height = work;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, sx, sy, side, side, 0, 0, work, work);

    const data = ctx.getImageData(0, 0, work, work);
    key(data.data, job.chroma);
    feather(data.data, work, work);
    ctx.putImageData(data, 0, 0);

    const box = bounds(data.data, work, work);
    if (!box) throw new Error('nothing left after keying, try another backdrop colour');

    const size = job.size || 256;
    const pad = Math.round(size * (job.padding == null ? 0.08 : job.padding));
    const fit = Math.min((size - pad * 2) / box.w, (size - pad * 2) / box.h);
    const dw = Math.round(box.w * fit), dh = Math.round(box.h * fit);

    const out = document.createElement('canvas');
    out.width = out.height = size;
    const o = out.getContext('2d');
    o.imageSmoothingQuality = 'high';
    o.drawImage(c, box.x, box.y, box.w, box.h, Math.round((size - dw) / 2), Math.round((size - dh) / 2), dw, dh);
    return out.toDataURL('image/png');
  }

  return { run };
})();
