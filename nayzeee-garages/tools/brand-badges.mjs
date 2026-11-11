#!/usr/bin/env node
/**
 * nayzeee-garages: brand logo pipeline for the key fob art (web/public/brands).
 *
 *   node tools/brand-badges.mjs optimize   shrink every web/public/brands/<slug>.glb in place
 *   node tools/brand-badges.mjs render     draw web/public/brands/png/<slug>.png (256 px badges)
 *   node tools/brand-badges.mjs all        both, in that order
 *
 * optimize: no external tool needed (the meshoptimizer encoder that web/node_modules already
 * carries, a dependency of @types/three). Per primitive: vertex cache + fetch order, positions
 * quantised to normalised int16 (one uniform scale + offset on the node, so normals stay
 * exact), normals octahedral 12-bit, UV0 normalised uint16 when it lies in 0..1, the unused
 * second UV set dropped, then EXT_meshopt_compression on every vertex / index buffer
 * (KHR_mesh_quantization). three's GLTFLoader reads it with MeshoptDecoder. Files that already
 * use EXT_meshopt_compression are skipped, so the command can be run again safely.
 *
 * render: starts a tiny local HTTP server for web/, opens headless Chromium (Playwright) with
 * WebGL (SwiftShader), loads each optimised GLB with three.js, lights it like a studio chrome
 * emblem and saves a transparent PNG. Re-run after adding / changing a logo.
 *
 * The logos are the 402 Studio "GTA V 3D logos" pack: keep SOURCES.txt and USAGE.txt next to
 * them (the pack's terms).
 */
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'web');
const BRANDS = path.join(WEB, 'public', 'brands');
const PNG_DIR = path.join(BRANDS, 'png');
const PNG_SIZE = 256;

/* ───────────────────────────── GLB io ───────────────────────────── */

function readGlb(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32LE(0) !== 0x46546c67) throw new Error(`${file}: not a GLB`);
  let off = 12;
  let json = null;
  let bin = null;
  while (off < b.length) {
    const len = b.readUInt32LE(off);
    const type = b.readUInt32LE(off + 4);
    const data = b.subarray(off + 8, off + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(data.toString('utf8'));
    else if (type === 0x004e4942) bin = Buffer.from(data);
    off += 8 + len;
  }
  return { json, bin };
}

function pad4(buf, fill) {
  const extra = (4 - (buf.length % 4)) % 4;
  return extra ? Buffer.concat([buf, Buffer.alloc(extra, fill)]) : buf;
}

function writeGlb(file, json, bin) {
  const jsonBuf = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20);
  const binBuf = pad4(bin, 0);
  const total = 12 + 8 + jsonBuf.length + 8 + binBuf.length;
  const head = Buffer.alloc(12);
  head.writeUInt32LE(0x46546c67, 0);
  head.writeUInt32LE(2, 4);
  head.writeUInt32LE(total, 8);
  const jh = Buffer.alloc(8);
  jh.writeUInt32LE(jsonBuf.length, 0);
  jh.writeUInt32LE(0x4e4f534a, 4);
  const bh = Buffer.alloc(8);
  bh.writeUInt32LE(binBuf.length, 0);
  bh.writeUInt32LE(0x004e4942, 4);
  fs.writeFileSync(file, Buffer.concat([head, jh, jsonBuf, bh, binBuf]));
  return total;
}

const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };

/** Accessor data as a typed array (float / uint16 / uint32 only: what the pack uses). */
function readAccessor(json, bin, index) {
  const acc = json.accessors[index];
  const view = json.bufferViews[acc.bufferView];
  const comps = COMPONENTS[acc.type];
  const Ctor = acc.componentType === 5126 ? Float32Array : acc.componentType === 5125 ? Uint32Array
    : acc.componentType === 5123 ? Uint16Array : null;
  if (!Ctor) throw new Error(`unsupported componentType ${acc.componentType}`);
  const stride = view.byteStride || comps * Ctor.BYTES_PER_ELEMENT;
  const start = (view.byteOffset || 0) + (acc.byteOffset || 0);
  const out = new Ctor(acc.count * comps);
  const src = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);
  for (let i = 0; i < acc.count; i++) {
    for (let c = 0; c < comps; c++) {
      const at = start + i * stride + c * Ctor.BYTES_PER_ELEMENT;
      out[i * comps + c] = Ctor === Float32Array ? src.getFloat32(at, true)
        : Ctor === Uint32Array ? src.getUint32(at, true) : src.getUint16(at, true);
    }
  }
  return out;
}

/* ───────────────────────────── optimize ───────────────────────────── */

async function loadEncoder() {
  const req = createRequire(path.join(WEB, 'package.json'));
  let entry;
  try {
    entry = req.resolve('meshoptimizer/meshopt_encoder.module.js');
  } catch {
    throw new Error('meshoptimizer is not installed in web/node_modules (cd web && npm install)');
  }
  const mod = await import(pathToFileURL(entry).href);
  await mod.MeshoptEncoder.ready;
  return mod.MeshoptEncoder;
}

async function optimizeFile(file, enc) {
  const { json, bin } = readGlb(file);
  if ((json.extensionsUsed || []).includes('EXT_meshopt_compression')) return null;
  const before = fs.statSync(file).size;
  const chunks = [];
  let length = 0;
  const views = [];
  const accessors = [];
  const push = (buf) => {
    const at = length;
    const b = pad4(Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength), 0);
    chunks.push(b);
    length += b.length;
    return { at, len: buf.byteLength };
  };
  // compressed bufferView: data in buffer 0 (meshopt stream), size declared on the fallback buffer 1
  let fallbackLength = 0;
  const compressedView = (raw, count, stride, mode, filter, target) => {
    const data = enc.encodeGltfBuffer(raw, count, stride, mode);
    const { at, len } = push(data);
    const byteLength = count * stride;
    const view = {
      buffer: 1, byteOffset: fallbackLength, byteLength,
      extensions: { EXT_meshopt_compression: { buffer: 0, byteOffset: at, byteLength: len, byteStride: stride, mode, count, ...(filter ? { filter } : {}) } },
    };
    if (mode === 'ATTRIBUTES') view.byteStride = stride;
    if (target) view.target = target;
    fallbackLength += Math.ceil(byteLength / 4) * 4;
    views.push(view);
    return views.length - 1;
  };
  const rawView = (buf) => {
    const { at, len } = push(buf);
    views.push({ buffer: 0, byteOffset: at, byteLength: len });
    return views.length - 1;
  };

  // images first (kept as they are)
  const images = (json.images || []).map((img) => {
    if (img.bufferView === undefined) return img;
    const v = json.bufferViews[img.bufferView];
    const data = bin.subarray(v.byteOffset || 0, (v.byteOffset || 0) + v.byteLength);
    return { ...img, bufferView: rawView(data) };
  });

  const meshNodes = new Map();
  (json.nodes || []).forEach((n, i) => {
    if (n.mesh !== undefined) meshNodes.set(n.mesh, [...(meshNodes.get(n.mesh) || []), i]);
  });

  const meshes = json.meshes.map((mesh, mi) => {
    // one uniform box per mesh (all of its primitives), applied as the node's scale + offset
    let min = [Infinity, Infinity, Infinity];
    let max = [-Infinity, -Infinity, -Infinity];
    for (const p of mesh.primitives) {
      const pos = readAccessor(json, bin, p.attributes.POSITION);
      for (let i = 0; i < pos.length; i += 3) {
        for (let c = 0; c < 3; c++) {
          min[c] = Math.min(min[c], pos[i + c]);
          max[c] = Math.max(max[c], pos[i + c]);
        }
      }
    }
    const center = [0, 1, 2].map((c) => (min[c] + max[c]) / 2);
    const half = Math.max(...[0, 1, 2].map((c) => (max[c] - min[c]) / 2), 1e-6);
    for (const ni of meshNodes.get(mi) || []) {
      const node = json.nodes[ni];
      if (node.matrix || node.rotation || node.scale || node.translation) {
        throw new Error(`${file}: node ${ni} already has a transform (not handled)`);
      }
      node.translation = center;
      node.scale = [half, half, half];
    }

    const primitives = mesh.primitives.map((p) => {
      const pos = readAccessor(json, bin, p.attributes.POSITION);
      const nrm = p.attributes.NORMAL !== undefined ? readAccessor(json, bin, p.attributes.NORMAL) : null;
      const uv = p.attributes.TEXCOORD_0 !== undefined ? readAccessor(json, bin, p.attributes.TEXCOORD_0) : null;
      const count = pos.length / 3;
      const indices = p.indices !== undefined ? Uint32Array.from(readAccessor(json, bin, p.indices))
        : Uint32Array.from({ length: count }, (_, i) => i);
      const [remap, unique] = enc.reorderMesh(indices, true, true);
      const attributes = {};

      // positions: normalised int16 xyz + padding
      const qp = new Int16Array(unique * 4);
      const qmin = [Infinity, Infinity, Infinity];
      const qmax = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i < count; i++) {
        const n = remap[i];
        if (n === 0xffffffff) continue;
        for (let c = 0; c < 3; c++) {
          const v = Math.max(-32767, Math.min(32767, Math.round(((pos[i * 3 + c] - center[c]) / half) * 32767)));
          qp[n * 4 + c] = v;
        }
      }
      // accessor min / max of a normalised accessor hold the raw integer values (glTF 2.0)
      for (let n = 0; n < unique; n++) {
        for (let c = 0; c < 3; c++) {
          qmin[c] = Math.min(qmin[c], qp[n * 4 + c]);
          qmax[c] = Math.max(qmax[c], qp[n * 4 + c]);
        }
      }
      accessors.push({ bufferView: compressedView(new Uint8Array(qp.buffer), unique, 8, 'ATTRIBUTES', null, 34962),
        componentType: 5122, normalized: true, count: unique, type: 'VEC3', min: qmin, max: qmax });
      attributes.POSITION = accessors.length - 1;

      if (nrm) {
        const f = new Float32Array(unique * 4);
        for (let i = 0; i < count; i++) {
          const n = remap[i];
          if (n === 0xffffffff) continue;
          const x = nrm[i * 3], y = nrm[i * 3 + 1], z = nrm[i * 3 + 2];
          const l = Math.hypot(x, y, z) || 1;
          f[n * 4] = x / l;
          f[n * 4 + 1] = y / l;
          f[n * 4 + 2] = z / l;
        }
        const filtered = enc.encodeFilterOct(f, unique, 8, 12);
        accessors.push({ bufferView: compressedView(filtered, unique, 8, 'ATTRIBUTES', 'OCTAHEDRAL', 34962),
          componentType: 5122, normalized: true, count: unique, type: 'VEC3' });
        attributes.NORMAL = accessors.length - 1;
      }

      if (uv) {
        let inRange = true;
        for (let i = 0; i < uv.length; i++) if (uv[i] < 0 || uv[i] > 1) { inRange = false; break; }
        if (inRange) {
          const q = new Uint16Array(unique * 2);
          for (let i = 0; i < count; i++) {
            const n = remap[i];
            if (n === 0xffffffff) continue;
            q[n * 2] = Math.round(uv[i * 2] * 65535);
            q[n * 2 + 1] = Math.round(uv[i * 2 + 1] * 65535);
          }
          accessors.push({ bufferView: compressedView(new Uint8Array(q.buffer), unique, 4, 'ATTRIBUTES', null, 34962),
            componentType: 5123, normalized: true, count: unique, type: 'VEC2' });
        } else {
          const q = new Float32Array(unique * 2);
          for (let i = 0; i < count; i++) {
            const n = remap[i];
            if (n === 0xffffffff) continue;
            q[n * 2] = uv[i * 2];
            q[n * 2 + 1] = uv[i * 2 + 1];
          }
          accessors.push({ bufferView: compressedView(new Uint8Array(q.buffer), unique, 8, 'ATTRIBUTES', null, 34962),
            componentType: 5126, count: unique, type: 'VEC2' });
        }
        attributes.TEXCOORD_0 = accessors.length - 1;
      }

      const small = unique <= 65535;
      const idx = small ? Uint16Array.from(indices) : indices;
      accessors.push({ bufferView: compressedView(new Uint8Array(idx.buffer, idx.byteOffset, idx.byteLength), indices.length,
        small ? 2 : 4, 'TRIANGLES', null, 34963), componentType: small ? 5123 : 5125, count: indices.length, type: 'SCALAR' });
      const out = { ...p, attributes, indices: accessors.length - 1 };
      return out;
    });
    return { ...mesh, primitives };
  });

  // texture coordinates of the materials point at TEXCOORD_0 only (the pack never uses set 1)
  const used = new Set(json.extensionsUsed || []);
  used.add('EXT_meshopt_compression');
  used.add('KHR_mesh_quantization');
  const required = new Set(json.extensionsRequired || []);
  required.add('EXT_meshopt_compression');
  required.add('KHR_mesh_quantization');
  const binOut = Buffer.concat(chunks);
  const out = {
    ...json,
    asset: { ...json.asset, generator: 'nayzeee-garages tools/brand-badges.mjs (meshopt)' },
    extensionsUsed: [...used],
    extensionsRequired: [...required],
    buffers: [{ byteLength: binOut.length }, { byteLength: fallbackLength, extensions: { EXT_meshopt_compression: { fallback: true } } }],
    bufferViews: views,
    accessors,
    images,
    meshes,
  };
  const after = writeGlb(file, out, binOut);
  return { before, after };
}

async function optimize() {
  const enc = await loadEncoder();
  const files = fs.readdirSync(BRANDS).filter((f) => f.endsWith('.glb')).sort();
  let before = 0;
  let after = 0;
  for (const f of files) {
    const res = await optimizeFile(path.join(BRANDS, f), enc);
    if (!res) {
      console.log(`${f}: already optimised`);
      continue;
    }
    before += res.before;
    after += res.after;
    console.log(`${f}: ${(res.before / 1024).toFixed(0)} KB -> ${(res.after / 1024).toFixed(0)} KB`);
  }
  if (before) console.log(`total ${(before / 1048576).toFixed(2)} MB -> ${(after / 1048576).toFixed(2)} MB`);
}

/* ───────────────────────────── render ───────────────────────────── */

const RENDER_PAGE = `<!doctype html><html><head><meta charset="utf-8">
<script type="importmap">{"imports":{"three":"/node_modules/three/build/three.module.js","three/addons/":"/node_modules/three/examples/jsm/"}}</script>
</head><body style="margin:0;background:transparent">
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
const SIZE = ${PNG_SIZE};
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(SIZE * 2, SIZE * 2);
renderer.setClearColor(0x000000, 0);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.25;
document.body.appendChild(renderer.domElement);
const pmrem = new THREE.PMREMGenerator(renderer);
// studio: dark floor to grey ceiling gradient + a few soft boxes (same set-up as BrandLogo3D)
function studio() {
  const s = new THREE.Scene();
  const geo = new THREE.SphereGeometry(10, 48, 24);
  const pos = geo.attributes.position;
  const col = [];
  for (let i = 0; i < pos.count; i++) {
    const t = (pos.getY(i) / 10 + 1) / 2;
    const c = 0.03 + 0.55 * Math.pow(t, 1.7);
    col.push(c, c, c * 1.03);
  }
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  s.add(new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
  const panel = (w, h, x, y, z, k, hex) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(hex).multiplyScalar(k), side: THREE.DoubleSide }));
    m.position.set(x, y, z);
    m.lookAt(0, 0, 0);
    s.add(m);
  };
  panel(5, 1.6, -3, 4.5, 4, 7, '#ffffff');
  panel(1, 6, 5.5, 0.5, 2.5, 3.2, '#ffffff');
  panel(5, 0.8, 0, -4.5, 3, 1.4, '#8fe9df');
  panel(9, 2.5, 0, 2.5, -6, 1.1, '#ffffff');
  panel(7, 3.2, 1.2, 1.6, 7, 1.9, '#ffffff');
  panel(3, 3, -6, -1, 5, 0.9, '#ffffff');
  return pmrem.fromScene(s, 0.015).texture;
}
const env = studio();
const loader = new GLTFLoader();
loader.setMeshoptDecoder(MeshoptDecoder);
window.renderBadge = async (url) => {
  const gltf = await loader.loadAsync(url);
  const scene = new THREE.Scene();
  scene.environment = env;
  const root = gltf.scene;
  // the emblems face +Z; a slight turn shows the chrome bevel
  root.rotation.y = -0.28;
  root.rotation.x = 0.16;
  scene.add(root);
  root.traverse((o) => {
    if (o.isMesh && o.material) {
      o.material.envMapIntensity = 1.4;
      o.material.metalness = Math.max(o.material.metalness ?? 1, 0.95);
      o.material.roughness = Math.min(Math.max(o.material.roughness ?? 0.12, 0.12), 0.32);
    }
  });
  const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(-1.5, 2, 3); scene.add(key);
  const rim = new THREE.DirectionalLight(0x9fe8e0, 0.7); rim.position.set(2, -1, 1.5); scene.add(rim);
  const box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  root.position.sub(center);
  const span = Math.max(size.x, size.y) * 1.1;
  const fov = 24;
  const dist = span / 2 / Math.tan((fov / 2) * Math.PI / 180) + size.z;
  const cam = new THREE.PerspectiveCamera(fov, 1, dist / 50, dist * 4);
  cam.position.set(0, 0, dist);
  cam.lookAt(0, 0, 0);
  renderer.render(scene, cam);
  // downsample 2x (supersampled edges) into a 256 px canvas
  const out = document.createElement('canvas');
  out.width = SIZE; out.height = SIZE;
  const ctx = out.getContext('2d');
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(renderer.domElement, 0, 0, SIZE, SIZE);
  scene.traverse((o) => { if (o.isMesh) { o.geometry.dispose(); } });
  return out.toDataURL('image/png');
};
window.ready = true;
</script></body></html>`;

function serve() {
  const types = { '.js': 'text/javascript', '.glb': 'model/gltf-binary', '.html': 'text/html', '.png': 'image/png' };
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent((req.url || '/').split('?')[0]);
    if (url === '/' || url === '/render.html') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(RENDER_PAGE);
      return;
    }
    const file = path.normalize(path.join(WEB, url));
    if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function render() {
  const req = createRequire(path.join(WEB, 'package.json'));
  let playwright;
  try {
    playwright = req('playwright');
  } catch {
    playwright = createRequire(import.meta.url)('playwright');
  }
  fs.mkdirSync(PNG_DIR, { recursive: true });
  const server = await serve();
  const port = server.address().port;
  const browser = await playwright.chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  try {
    const page = await browser.newPage();
    page.on('console', (m) => { if (m.type() === 'error') console.error('page:', m.text()); });
    page.on('pageerror', (e) => console.error('page error:', e.message));
    await page.goto(`http://127.0.0.1:${port}/render.html`);
    await page.waitForFunction(() => window.ready === true, null, { timeout: 30000 });
    const files = fs.readdirSync(BRANDS).filter((f) => f.endsWith('.glb')).sort();
    for (const f of files) {
      const slug = f.replace(/\.glb$/, '');
      const dataUrl = await page.evaluate((u) => window.renderBadge(u), `/public/brands/${f}`);
      const png = Buffer.from(dataUrl.split(',')[1], 'base64');
      fs.writeFileSync(path.join(PNG_DIR, `${slug}.png`), png);
      console.log(`${slug}.png ${(png.length / 1024).toFixed(1)} KB`);
    }
  } finally {
    await browser.close();
    server.close();
  }
}

const cmd = process.argv[2] || 'all';
if (cmd === 'optimize' || cmd === 'all') await optimize();
if (cmd === 'render' || cmd === 'all') await render();
if (!['optimize', 'render', 'all'].includes(cmd)) {
  console.error('usage: node tools/brand-badges.mjs optimize|render|all');
  process.exit(1);
}
