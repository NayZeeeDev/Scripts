// Wig Studio image pipeline: decode the screenshot, key out the background, crop, resize, save.
// Plain Node (zlib only), so there's no yarn / npm install step.
// The chroma key + resize approach follows uz_AutoShot (Apache-2.0).

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const RESOURCE = GetCurrentResourceName();
const ROOT = GetResourcePath(RESOURCE);
const SHOTS = path.resolve(path.join(ROOT, 'shots'));
const INDEX = path.join(SHOTS, 'index.json');
const KEY_RE = /^([mf])\/(\d{1,4})_(\d{1,3})$/;
const MAX_B64 = Math.ceil(24 * 1024 * 1024 * 4 / 3);

/* ─────────────── PNG ─────────────── */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

// returns { width, height, data: RGBA Buffer }. 8-bit RGB / RGBA, non-interlaced.
function decodePNG(buf) {
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIG)) throw new Error('not a png');
  let pos = 8, width = 0, height = 0, depth = 0, type = 0, interlace = 0;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const kind = buf.toString('ascii', pos + 4, pos + 8);
    const body = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === 'IHDR') {
      width = body.readUInt32BE(0); height = body.readUInt32BE(4);
      depth = body[8]; type = body[9]; interlace = body[12];
    } else if (kind === 'IDAT') idat.push(body);
    else if (kind === 'IEND') break;
    pos += 12 + len;
  }
  if (depth !== 8 || (type !== 6 && type !== 2) || interlace !== 0) throw new Error(`unsupported png (depth ${depth}, type ${type}, interlace ${interlace})`);
  if (!width || !height || width > 8192 || height > 8192) throw new Error('bad png size');

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = type === 6 ? 4 : 3;
  const stride = width * bpp;
  if (raw.length < (stride + 1) * height) throw new Error('truncated png');
  const px = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const src = y * (stride + 1) + 1, dst = y * stride, prev = dst - stride;
    for (let x = 0; x < stride; x++) {
      const v = raw[src + x];
      const a = x >= bpp ? px[dst + x - bpp] : 0;
      const b = y > 0 ? px[prev + x] : 0;
      const c = x >= bpp && y > 0 ? px[prev + x - bpp] : 0;
      let out;
      switch (f) {
        case 0: out = v; break;
        case 1: out = v + a; break;
        case 2: out = v + b; break;
        case 3: out = v + ((a + b) >> 1); break;
        case 4: out = v + paeth(a, b, c); break;
        default: throw new Error('bad png filter ' + f);
      }
      px[dst + x] = out & 0xff;
    }
  }
  if (bpp === 4) return { width, height, data: px };
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0, j = 0; i < px.length; i += 3, j += 4) {
    rgba[j] = px[i]; rgba[j + 1] = px[i + 1]; rgba[j + 2] = px[i + 2]; rgba[j + 3] = 255;
  }
  return { width, height, data: rgba };
}

function chunk(kind, body) {
  const len = Buffer.alloc(4); len.writeUInt32BE(body.length);
  const kb = Buffer.from(kind, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([kb, body])));
  return Buffer.concat([len, kb, body, crc]);
}

function encodePNG(img) {
  const { width, height, data } = img;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    // filter 1 (sub) compresses photos far better than none
    const o = y * (stride + 1), s = y * stride;
    raw[o] = 1;
    for (let x = 0; x < stride; x++) raw[o + 1 + x] = (data[s + x] - (x >= 4 ? data[s + x - 4] : 0)) & 0xff;
  }
  return Buffer.concat([SIG, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

/* ─────────────── image ops ─────────────── */

function chromaKey(img, mode) {
  const d = img.data, w = img.width, h = img.height;
  const magenta = mode !== 'green';
  for (let i = 0; i < d.length; i += 4) {
    const r = d[i], g = d[i + 1], b = d[i + 2];
    let k = 0;
    if (magenta) {
      const ro = r - g, bo = b - g, minOver = Math.min(ro, bo), prim = Math.min(r, b);
      if (minOver > 0 && prim > 10) {
        k = Math.min(1, (ro + bo) / (r + b + 1)) * (minOver < 20 ? minOver / 20 : 1) * (prim < 40 ? (prim - 10) / 30 : 1);
      }
    } else {
      const ro = g - r, bo = g - b, minOver = Math.min(ro, bo);
      if (minOver > 0 && g > 10) {
        k = Math.min(1, (ro + bo) / (g + 1)) * (minOver < 20 ? minOver / 20 : 1) * (g < 40 ? (g - 10) / 30 : 1);
      }
    }
    if (k > 0) {
      d[i + 3] = (255 * (1 - k) + 0.5) | 0;
      if (magenta) { d[i] = (r - (r - g) * k + 0.5) | 0; d[i + 2] = (b - (b - g) * k + 0.5) | 0; }
      else { const cap = Math.max(r, b); d[i + 1] = (g - (g - cap) * k + 0.5) | 0; }
    }
  }
  // soften the cut-out edge (2 passes of a 5x5 box on alpha, edges only)
  const R = 2, K = (R * 2 + 1) ** 2, a = new Uint8Array(w * h);
  for (let pass = 0; pass < 2; pass++) {
    for (let i = 0; i < w * h; i++) a[i] = d[i * 4 + 3];
    for (let y = R; y < h - R; y++) {
      for (let x = R; x < w - R; x++) {
        const idx = y * w + x, v = a[idx];
        if ((v === 0 || v === 255) && a[idx - 1] === v && a[idx + 1] === v && a[idx - w] === v && a[idx + w] === v) continue;
        let sum = 0;
        for (let ky = -R; ky <= R; ky++) for (let kx = -R; kx <= R; kx++) sum += a[idx + ky * w + kx];
        d[idx * 4 + 3] = (sum / K + 0.5) | 0;
      }
    }
  }
  return img;
}

// centre-crop to the target aspect, then area-average down (or bilinear up)
function cropResize(img, tw, th) {
  const sw = img.width, sh = img.height, sd = img.data;
  let cx = 0, cy = 0, cw = sw, chh = sh;
  if (sw / sh > tw / th) { cw = Math.round(sh * tw / th); cx = Math.round((sw - cw) / 2); }
  else if (sw / sh < tw / th) { chh = Math.round(sw * th / tw); cy = Math.round((sh - chh) / 2); }
  const out = Buffer.alloc(tw * th * 4);
  const xr = cw / tw, yr = chh / th;
  for (let y = 0; y < th; y++) {
    const y0 = cy + y * yr, y1 = cy + (y + 1) * yr;
    for (let x = 0; x < tw; x++) {
      const x0 = cx + x * xr, x1 = cx + (x + 1) * xr;
      let r = 0, g = 0, b = 0, al = 0, tot = 0;
      for (let sy = Math.floor(y0); sy < Math.min(Math.ceil(y1), cy + chh); sy++) {
        const wy = Math.min(sy + 1, y1) - Math.max(sy, y0);
        for (let sx = Math.floor(x0); sx < Math.min(Math.ceil(x1), cx + cw); sx++) {
          const wgt = wy * (Math.min(sx + 1, x1) - Math.max(sx, x0));
          if (wgt <= 0) continue;
          const si = (sy * sw + sx) * 4, aw = sd[si + 3] * wgt;
          // premultiplied so the keyed background doesn't bleed into the edges
          r += sd[si] * aw; g += sd[si + 1] * aw; b += sd[si + 2] * aw; al += aw; tot += wgt;
        }
      }
      const di = (y * tw + x) * 4;
      if (al > 0) { out[di] = (r / al + 0.5) | 0; out[di + 1] = (g / al + 0.5) | 0; out[di + 2] = (b / al + 0.5) | 0; }
      out[di + 3] = tot > 0 ? (al / tot + 0.5) | 0 : 0;
    }
  }
  return { width: tw, height: th, data: out };
}

/* ─────────────── index ─────────────── */

const index = new Set();

function scan() {
  index.clear();
  for (const m of ['m', 'f']) {
    const dir = path.join(SHOTS, m);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      const mm = /^(\d+)_(\d+)\.png$/.exec(f);
      if (mm) index.add(`${m}/${mm[1]}_${mm[2]}`);
    }
  }
  writeIndex();
}

function writeIndex() {
  try {
    fs.mkdirSync(SHOTS, { recursive: true });
    fs.writeFileSync(INDEX, JSON.stringify([...index].sort()));
  } catch (e) {
    console.log(`^1[${RESOURCE}]^7 studio index error: ${e.message}`);
  }
}

try { scan(); } catch (e) { console.log(`^1[${RESOURCE}]^7 studio scan error: ${e.message}`); }
emit('nz-wig:studio:indexed');

/* ─────────────── uploads ─────────────── */

function allowed(src) {
  const ace = GetConvar('nzwig_studio_ace', 'command.wigstudio');
  return IsPlayerAceAllowed(String(src), ace);
}

function stripUri(b64) {
  if (typeof b64 !== 'string') return '';
  const i = b64.indexOf(',');
  return b64.startsWith('data:') && i !== -1 ? b64.slice(i + 1) : b64;
}

onNet('nz-wig:studioUpload', (payload) => {
  const src = global.source;
  if (!allowed(src)) return console.log(`^1[${RESOURCE}]^7 refused studio upload from ${src} (no ace)`);
  if (!payload || typeof payload !== 'object') return;
  const key = typeof payload.key === 'string' ? payload.key : '';
  const m = KEY_RE.exec(key);
  if (!m) return console.log(`^1[${RESOURCE}]^7 refused studio upload: bad key ${key}`);
  if (typeof payload.image !== 'string' || !payload.image.length || payload.image.length > MAX_B64) return;

  const w = Math.min(Math.max(parseInt(payload.width, 10) || 256, 32), 1024);
  const h = Math.min(Math.max(parseInt(payload.height, 10) || 256, 32), 1024);
  try {
    let img = decodePNG(Buffer.from(stripUri(payload.image), 'base64'));
    if (payload.transparent !== false) img = chromaKey(img, payload.chroma === 'green' ? 'green' : 'magenta');
    img = cropResize(img, w, h);
    const file = path.resolve(path.join(SHOTS, m[1], `${m[2]}_${m[3]}.png`));
    if (!file.startsWith(SHOTS + path.sep)) return;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, encodePNG(img));
    index.add(key);
    writeIndex();
    emit('nz-wig:studio:saved', key);
    emitNet('nz-wig:c:studioSaved', src, key);
  } catch (e) {
    console.log(`^1[${RESOURCE}]^7 studio upload failed (${key}): ${e.message}`);
    emitNet('nz-wig:c:studioSaved', src, key, e.message);
  }
});

onNet('nz-wig:studioDelete', (key) => {
  const src = global.source;
  if (!allowed(src) || typeof key !== 'string' || !KEY_RE.test(key)) return;
  const m = KEY_RE.exec(key);
  const file = path.resolve(path.join(SHOTS, m[1], `${m[2]}_${m[3]}.png`));
  if (!file.startsWith(SHOTS + path.sep)) return;
  try { fs.unlinkSync(file); } catch (e) { /* already gone */ }
  index.delete(key);
  writeIndex();
  emit('nz-wig:studio:saved', key);
});


if (typeof module !== 'undefined') module.exports = { decodePNG, encodePNG, chromaKey, cropResize, crc32 };
