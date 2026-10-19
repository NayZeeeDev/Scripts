// Shared helpers for the item / tool-belt renders: materials, procedural textures, geometry.
// Units are centimetres, three.js axes: +Y up, the object's front faces +Z, it rests on y = 0.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export { THREE };
export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const TAU = Math.PI * 2;
export const deg = d => d * Math.PI / 180;

/* ───────────────────────────── random + noise ───────────────────────────── */
export function rng(seed = 1) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}
function hash2(x, y, seed) {
  let h = (x * 374761393 + y * 668265263 + seed * 2246822519) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
// tileable value noise on a period p grid
export function vnoise(x, y, p, seed = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const m = n => ((n % p) + p) % p;
  const a = hash2(m(xi), m(yi), seed), b = hash2(m(xi + 1), m(yi), seed);
  const c = hash2(m(xi), m(yi + 1), seed), d = hash2(m(xi + 1), m(yi + 1), seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
export function fbm(x, y, p, oct = 4, seed = 0) {
  let s = 0, a = 0.5, f = 1, n = 0;
  for (let i = 0; i < oct; i++) { s += a * vnoise(x * f, y * f, p * f, seed + i * 17); n += a; a *= 0.5; f *= 2; }
  return s / n;
}

/* ───────────────────────────── canvas textures ───────────────────────────── */
export function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
// draw(ctx, w, h) → sRGB colour texture
export function canvasTex(w, h, draw, { srgb = true, repeat = null, flipY = true } = {}) {
  const c = canvas(w, h);
  const g = c.getContext('2d');
  draw(g, w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.anisotropy = 8;
  t.flipY = flipY;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]); }
  t.needsUpdate = true;
  return t;
}
// height(u, v) in [0..1] (u, v in [0..1)) → tangent-space normal map
export function normalTex(size, height, { strength = 2, repeat = [1, 1] } = {}) {
  const H = new Float32Array(size * size);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) H[y * size + x] = height(x / size, y / size);
  const c = canvas(size, size), g = c.getContext('2d'), img = g.createImageData(size, size);
  const at = (x, y) => H[((y + size) % size) * size + ((x + size) % size)];
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const dx = (at(x + 1, y) - at(x - 1, y)) * strength, dy = (at(x, y + 1) - at(x, y - 1)) * strength;
    const l = Math.hypot(dx, dy, 1), i = (y * size + x) * 4;
    img.data[i] = (-dx / l * 0.5 + 0.5) * 255; img.data[i + 1] = (dy / l * 0.5 + 0.5) * 255; img.data[i + 2] = (1 / l * 0.5 + 0.5) * 255; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.NoColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]); t.anisotropy = 8;
  return t;
}
const texCache = new Map();
const cached = (k, f) => { if (!texCache.has(k)) texCache.set(k, f()); return texCache.get(k); };
const cloneRep = (t, rep) => { if (!rep) return t; const c = t.clone(); c.repeat.set(rep[0], rep[1]); c.needsUpdate = true; return c; };
export const NT = {
  // woven nylon webbing / bag cordura
  weave: rep => cloneRep(cached('weave', () => normalTex(256, (u, v) => {
    const f = 32, a = Math.sin(u * TAU * f), b = Math.sin(v * TAU * f);
    const over = (Math.floor(u * f * 2) + Math.floor(v * f * 2)) % 2 ? a * 0.5 + 0.5 : b * 0.5 + 0.5;
    return over * 0.6 + fbm(u * 16, v * 16, 16, 2, 3) * 0.4;
  }, { strength: 3 })), rep),
  // crepe bandage / gauze
  // crepe: crinkles run across the strip (constant u), u = along the bandage
  crepe: rep => cloneRep(cached('crepe', () => normalTex(256, (u, v) => {
    const r = Math.sin(u * TAU * 24 + fbm(u * 4, v * 8, 4, 2, 5) * 5) * 0.5 + 0.5;
    return r * 0.75 + fbm(u * 32, v * 32, 32, 2, 7) * 0.25;
  }, { strength: 4 })), rep),
  gauze: rep => cloneRep(cached('gauze', () => normalTex(256, (u, v) => {
    const a = Math.abs(Math.sin(u * TAU * 40)), b = Math.abs(Math.sin(v * TAU * 40));
    return Math.max(a, b) * 0.8 + fbm(u * 16, v * 16, 16, 2, 9) * 0.2;
  }, { strength: 2.2 })), rep),
  // crumpled foil: random facets (voronoi cells with a random tilt)
  crinkle: rep => cloneRep(cached('crinkle', () => {
    const s = 512, c = canvas(s, s), g = c.getContext('2d'), img = g.createImageData(s, s), R = rng(77), N = 260;
    const pts = Array.from({ length: N }, () => [R() * s, R() * s, (R() - 0.5) * 1.3, (R() - 0.5) * 1.3]);
    for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
      let best = 1e9, bi = 0;
      for (let k = 0; k < N; k++) {
        let dx = Math.abs(x - pts[k][0]), dy = Math.abs(y - pts[k][1]);
        if (dx > s / 2) dx = s - dx; if (dy > s / 2) dy = s - dy;
        const d = dx * dx + dy * dy; if (d < best) { best = d; bi = k; }
      }
      const [, , nx, ny] = pts[bi], l = Math.hypot(nx, ny, 1), i = (y * s + x) * 4;
      img.data[i] = (nx / l * 0.5 + 0.5) * 255; img.data[i + 1] = (ny / l * 0.5 + 0.5) * 255; img.data[i + 2] = (1 / l * 0.5 + 0.5) * 255; img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.NoColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
    return t;
  }), rep),
  plaster: rep => cloneRep(cached('plaster', () => normalTex(256, (u, v) => fbm(u * 24, v * 24, 24, 4, 11), { strength: 3 })), rep),
  foam: rep => cloneRep(cached('foam', () => normalTex(256, (u, v) => fbm(u * 48, v * 48, 48, 3, 13), { strength: 2 })), rep),
  grain: rep => cloneRep(cached('grain', () => normalTex(256, (u, v) => fbm(u * 64, v * 64, 64, 2, 21), { strength: 0.8 })), rep),
  knurl: rep => cloneRep(cached('knurl', () => normalTex(128, (u, v) => {
    const a = Math.abs(((u + v) * 16) % 1 - 0.5), b = Math.abs(((u - v + 1) * 16) % 1 - 0.5);
    return 1 - Math.max(a, b) * 2;
  }, { strength: 6 })), rep),
  brushed: rep => cloneRep(cached('brushed', () => normalTex(256, (u, v) => fbm(u * 2, v * 128, 2, 2, 31) * 0.6 + vnoise(u * 4, v * 256, 4, 5) * 0.4, { strength: 1.2 })), rep),
  ribs: rep => cloneRep(cached('ribs', () => normalTex(128, (u, v) => Math.sin(v * TAU * 16) * 0.5 + 0.5, { strength: 4 })), rep),
  velcro: rep => cloneRep(cached('velcro', () => normalTex(256, (u, v) => fbm(u * 64, v * 64, 64, 2, 41) * 0.7 + (Math.sin(u * TAU * 64) * 0.5 + 0.5) * 0.3, { strength: 4 })), rep),
};

/* ───────────────────────────── materials ───────────────────────────── */
const C = c => new THREE.Color(c);
export const mat = {
  plastic: (color, o = {}) => new THREE.MeshPhysicalMaterial({ color: C(color), roughness: 0.38, metalness: 0, clearcoat: 0.25, clearcoatRoughness: 0.4, ...o }),
  matte: (color, o = {}) => new THREE.MeshStandardMaterial({ color: C(color), roughness: 0.75, metalness: 0, ...o }),
  rubber: (color, o = {}) => new THREE.MeshStandardMaterial({ color: C(color), roughness: 0.82, metalness: 0, normalMap: NT.grain([4, 4]), normalScale: new THREE.Vector2(0.3, 0.3), ...o }),
  steel: (o = {}) => new THREE.MeshStandardMaterial({ color: C(0xd9dde2), roughness: 0.2, metalness: 1, ...o }),
  satin: (o = {}) => new THREE.MeshStandardMaterial({ color: C(0xc9cdd2), roughness: 0.34, metalness: 1, normalMap: NT.brushed([1, 1]), normalScale: new THREE.Vector2(0.25, 0.25), ...o }),
  chrome: (o = {}) => new THREE.MeshStandardMaterial({ color: C(0xf2f4f6), roughness: 0.06, metalness: 1, ...o }),
  alu: (color = 0xc3c8ce, o = {}) => new THREE.MeshStandardMaterial({ color: C(color), roughness: 0.3, metalness: 1, ...o }),
  gold: (o = {}) => new THREE.MeshStandardMaterial({ color: C(0xe8c27a), roughness: 0.22, metalness: 1, ...o }),
  paper: (map, o = {}) => new THREE.MeshStandardMaterial({ map, color: C(0xffffff), roughness: 0.78, metalness: 0, ...o }),
  printed: (map, o = {}) => new THREE.MeshPhysicalMaterial({ map, color: C(0xffffff), roughness: 0.42, metalness: 0, clearcoat: 0.35, clearcoatRoughness: 0.3, ...o }),
  fabric: (color, o = {}) => new THREE.MeshStandardMaterial({ color: C(color), roughness: 0.92, metalness: 0, normalMap: NT.weave([6, 6]), normalScale: new THREE.Vector2(0.6, 0.6), ...o }),
  // clear glass/plastic: alpha follows the reflected light so highlights stay bright on a transparent background
  // clear glass: almost no diffuse (dark base colour), the look comes from the tinted reflections
  glass: (o = {}) => clearMat({ color: 0x0b0d0e, spec: 0xe8f6fb, roughness: 0.03, opacity: 0.1, envMapIntensity: 1.6, lum: 0.95, ...o }),
  film: (o = {}) => clearMat({ color: 0xf2f8fb, roughness: 0.16, opacity: 0.32, envMapIntensity: 1.3, ...o }),
  liquid: (color, o = {}) => clearMat({ color, roughness: 0.08, opacity: 0.7, envMapIntensity: 1.0, lum: 0.4, ...o }),
};
export function clearMat({ color, roughness, opacity, envMapIntensity = 1, lum = 0.85, side = THREE.DoubleSide, map = null, normalMap = null, normalScale = 1, clearcoat = 0.6, spec = 0xffffff }) {
  const m = new THREE.MeshPhysicalMaterial({
    color: C(color), roughness, metalness: 0, transparent: true, opacity, depthWrite: false, side, envMapIntensity,
    clearcoat, clearcoatRoughness: 0.05, specularIntensity: 1, specularColor: C(spec), ior: 1.5, map, normalMap,
  });
  if (normalMap) m.normalScale.set(normalScale, normalScale);
  m.onBeforeCompile = sh => {
    sh.fragmentShader = sh.fragmentShader.replace('#include <opaque_fragment>', `
      float nzLum = max(max(outgoingLight.r, outgoingLight.g), outgoingLight.b);
      gl_FragColor = vec4(outgoingLight, clamp(max(diffuseColor.a, nzLum * ${lum.toFixed(3)}), 0.0, 1.0));`);
  };
  m.customProgramCacheKey = () => 'nzclear' + lum;
  return m;
}
export function withNormal(m, nt, scale = 1) { m.normalMap = nt; m.normalScale = new THREE.Vector2(scale, scale); return m; }

/* ───────────────────────────── geometry ───────────────────────────── */
export function mesh(geo, material, { pos, rot, scale, order, shadow = true, name } = {}) {
  const m = new THREE.Mesh(geo, material);
  if (pos) m.position.set(pos[0], pos[1], pos[2]);
  if (rot) m.rotation.set(rot[0], rot[1], rot[2], rot[3] || 'XYZ');
  if (scale !== undefined) Array.isArray(scale) ? m.scale.set(scale[0], scale[1], scale[2]) : m.scale.setScalar(scale);
  if (order !== undefined) m.renderOrder = order;
  const transparent = Array.isArray(material) ? material.some(x => x.transparent) : material.transparent;
  m.castShadow = shadow && !transparent; m.receiveShadow = true;
  if (name) m.name = name;
  return m;
}
export function group(children = [], { pos, rot, scale } = {}) {
  const g = new THREE.Group();
  children.filter(Boolean).forEach(c => g.add(c));
  if (pos) g.position.set(pos[0], pos[1], pos[2]);
  if (rot) g.rotation.set(rot[0], rot[1], rot[2], rot[3] || 'XYZ');
  if (scale !== undefined) Array.isArray(scale) ? g.scale.set(scale[0], scale[1], scale[2]) : g.scale.setScalar(scale);
  return g;
}
// rounded box centred on the origin; materials can be an array [+x, -x, +y, -y, +z, -z]
export function rbox(w, h, d, r = 0.1, seg = 4) { return new RoundedBoxGeometry(w, h, d, seg, Math.min(r, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4)); }
// lathe from [[r, y], ...] (bottom → top); smooth = catmull-rom resample count
export function lathe(profile, { seg = 72, smooth = 0, phi = 0, len = TAU } = {}) {
  let pts = profile.map(([r, y]) => new THREE.Vector2(Math.max(r, 0), y));
  if (smooth) {
    const curve = new THREE.SplineCurve(pts);
    pts = curve.getSpacedPoints(smooth);
  }
  const g = new THREE.LatheGeometry(pts, seg, phi, len);
  g.computeVertexNormals();
  return g;
}
// simple lathe from a list of [r, y] with sharp segments but smooth normals around
export function cyl(r, h, { seg = 64, y = 0, r2 = r, open = false } = {}) {
  const g = new THREE.CylinderGeometry(r2, r, h, seg, 1, open);
  g.translate(0, y + h / 2, 0);
  return g;
}
// rounded cylinder (bevelled top + bottom edge)
export function rcyl(r, h, bev = 0.1, { seg = 64, y = 0 } = {}) {
  const b = Math.min(bev, r * 0.5, h * 0.5), p = [[0, 0]];
  for (let i = 0; i <= 6; i++) { const a = -Math.PI / 2 + (i / 6) * Math.PI / 2; p.push([r - b + Math.cos(a) * b, b + Math.sin(a) * b]); }
  for (let i = 0; i <= 6; i++) { const a = (i / 6) * Math.PI / 2; p.push([r - b + Math.cos(a) * b, h - b + Math.sin(a) * b]); }
  p.push([0, h]);
  const g = lathe(p, { seg });
  g.translate(0, y, 0);
  return g;
}
export function tube(points, radius, { closed = false, tubular = 0, radial = 16, tension = 0.5, type = 'catmullrom' } = {}) {
  const curve = new THREE.CatmullRomCurve3(points.map(p => Array.isArray(p) ? V3(...p) : p), closed, type, tension);
  const n = tubular || Math.max(24, Math.ceil(curve.getLength() / Math.max(radius * 0.8, 0.05)));
  return new THREE.TubeGeometry(curve, Math.min(n, 800), radius, radial, closed);
}
export function curve(points, { closed = false, tension = 0.5 } = {}) {
  return new THREE.CatmullRomCurve3(points.map(p => Array.isArray(p) ? V3(...p) : p), closed, 'catmullrom', tension);
}
// flat strap (rectangle w × t) swept along a path; `up` = the strap's width direction hint
// (a fixed vector or a function of t), uv: u along the path in cm, v across
export function strap(points, w, t, { closed = false, up = V3(0, 1, 0), steps = 0, tension = 0.5, round = 0.35, uScale = 1 } = {}) {
  const cv = Array.isArray(points) ? curve(points, { closed, tension }) : points;
  const L = cv.getLength(), n = steps || Math.min(600, Math.max(32, Math.ceil(L / 0.25)));
  const prof = [];
  const rr = Math.min(round, 1) * t / 2, hw = w / 2, ht = t / 2;
  // rounded-rect profile (x across width, y through thickness)
  const corner = (cx, cy, a0) => { for (let i = 0; i <= 3; i++) { const a = a0 + (i / 3) * Math.PI / 2; prof.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]); } };
  corner(hw - rr, ht - rr, 0); corner(-hw + rr, ht - rr, Math.PI / 2); corner(-hw + rr, -ht + rr, Math.PI); corner(hw - rr, -ht + rr, Math.PI * 1.5);
  const m = prof.length, pos = [], uv = [], idx = [];
  const T = V3(), N = V3(), B = V3(), P = V3();
  const perim = []; let acc = 0;
  for (let j = 0; j <= m; j++) { const a = prof[j % m], b = prof[(j + 1) % m]; perim.push(acc); acc += Math.hypot(b[0] - a[0], b[1] - a[1]); }
  for (let i = 0; i <= n; i++) {
    const s = closed ? i / n : i / n;
    cv.getPointAt(Math.min(s, 1), P); cv.getTangentAt(Math.min(s, 1), T);
    const u = typeof up === 'function' ? up(s, P) : up;
    B.copy(u).sub(T.clone().multiplyScalar(u.dot(T))).normalize();   // width direction
    N.crossVectors(T, B).normalize();                                     // thickness direction
    for (let j = 0; j <= m; j++) {
      const [x, y] = prof[j % m];
      pos.push(P.x + B.x * x + N.x * y, P.y + B.y * x + N.y * y, P.z + B.z * x + N.z * y);
      uv.push(s * L * uScale, perim[j] / acc);
    }
  }
  for (let i = 0; i < n; i++) for (let j = 0; j < m; j++) {
    const a = i * (m + 1) + j, b = (i + 1) * (m + 1) + j;
    idx.push(a, b, a + 1, b, b + 1, a + 1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  if (!closed) {   // end caps
    const caps = [];
    for (const s of [0, 1]) {
      cv.getPointAt(s, P); cv.getTangentAt(s, T);
      const u = typeof up === 'function' ? up(s, P) : up;
      B.copy(u).sub(T.clone().multiplyScalar(u.dot(T))).normalize(); N.crossVectors(T, B).normalize();
      const shape = new THREE.Shape(prof.map(([x, y]) => new THREE.Vector2(x, y)));
      const cg = new THREE.ShapeGeometry(shape);
      const M = new THREE.Matrix4().makeBasis(B, N, s ? T : T.clone().negate());
      if (!s) M.makeBasis(B.clone().negate(), N, T.clone().negate());
      if (!s) { const pa = cg.attributes.position; for (let k = 0; k < pa.count; k++) pa.setX(k, -pa.getX(k)); }
      M.setPosition(P);
      cg.applyMatrix4(M);
      caps.push(cg.toNonIndexed());
    }
    const gi = g.toNonIndexed();
    caps.forEach(c => { c.deleteAttribute('uv'); c.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(c.attributes.position.count * 2), 2)); });
    const merged = mergeGeometries([gi, ...caps]);
    merged.computeVertexNormals();
    return merged;
  }
  return g;
}
// soft sealed bag: w (x) × h (y) lying in the XY plane, bulging ±t/2 in z, welded seam of width `seam`
// shape(x, y) can override the inflation profile (0..1); returns [front, back] geometries whose
// UVs map the whole bag face (u: -x..+x, v: -y..+y)
export function pillow(w, h, t, { seam = 0.4, nx = 64, ny = 64, power = 0.5, front = 1, back = 1, ramp = 2.2, shape = null } = {}) {
  const geos = [];
  for (const side of [1, -1]) {
    const g = new THREE.PlaneGeometry(w, h, nx, ny);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), y = p.getY(i);
      const ix = Math.max(0, 1 - Math.abs(x) / (w / 2 - seam)), iy = Math.max(0, 1 - Math.abs(y) / (h / 2 - seam));
      let z = shape ? shape(x, y, ix, iy) : Math.pow(Math.min(1, ix * ramp) * Math.min(1, iy * ramp), power);
      z *= (t / 2) * (side > 0 ? front : back);
      p.setZ(i, side * Math.max(z, 0.006));
    }
    if (side < 0) { const idx = g.index.array; for (let i = 0; i < idx.length; i += 3) { const tmp = idx[i]; idx[i] = idx[i + 1]; idx[i + 1] = tmp; } }
    g.computeVertexNormals();
    geos.push(g);
  }
  return geos;
}
export function rrectShape(w, h, r, { cx = 0, cy = 0 } = {}) {
  const s = new THREE.Shape(), x = cx - w / 2, y = cy - h / 2;
  r = Math.min(r, w / 2, h / 2);
  s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  return s;
}
export function rrectPath(w, h, r, { cx = 0, cy = 0 } = {}) {
  const s = new THREE.Path(), x = cx - w / 2, y = cy - h / 2;
  r = Math.min(r, w / 2, h / 2);
  s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  return s;
}
export function circlePath(r, cx = 0, cy = 0, cw = false) { const p = new THREE.Path(); p.absarc(cx, cy, r, 0, TAU, cw); return p; }
// extrude a 2D shape (XY) by depth along +Z (centred), with a rounded bevel; UVs normalised to the shape bbox on caps
export function extrude(shape, depth, { bevel = 0.05, bevelSeg = 3, curveSeg = 24, center = true } = {}) {
  const g = new THREE.ExtrudeGeometry(shape, { depth: Math.max(depth - 2 * bevel, 0.001), bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: bevelSeg, curveSegments: curveSeg });
  if (center) g.translate(0, 0, -(depth - 2 * bevel) / 2);
  g.computeBoundingBox();
  const bb = g.boundingBox, uv = g.attributes.uv, p = g.attributes.position;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, (p.getX(i) - bb.min.x) / (bb.max.x - bb.min.x), (p.getY(i) - bb.min.y) / (bb.max.y - bb.min.y));
  g.computeVertexNormals();
  return g;
}
// cylinder-section label wrapped around the Y axis
// theta = direction (around Y, 0 = +Z, positive towards +X) that the label's u = focus faces
export function wrapLabel(radius, y0, y1, map, { theta = 0, len = TAU * 0.8, mat: m = null, seg = 64, focus = 0.5 } = {}) {
  const g = new THREE.CylinderGeometry(radius, radius, y1 - y0, seg, 1, true, theta - len * focus, len);
  g.translate(0, (y0 + y1) / 2, 0);
  const material = m || new THREE.MeshPhysicalMaterial({ map, roughness: 0.45, clearcoat: 0.3, clearcoatRoughness: 0.35, side: THREE.FrontSide });
  return mesh(g, material);
}
// flat decal quad (faces +Z before rotation), lifted to avoid z-fighting
export function decal(w, h, map, { pos = [0, 0, 0], rot = [0, 0, 0], rough = 0.5, transparent = true, coat = 0.2, metal = 0 } = {}) {
  const m = new THREE.MeshPhysicalMaterial({ map, roughness: rough, metalness: metal, transparent, clearcoat: coat, clearcoatRoughness: 0.3, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  if (transparent) { m.alphaTest = 0.02; m.depthWrite = false; m.transparent = true; }
  const me = mesh(new THREE.PlaneGeometry(w, h), m, { pos, rot });
  me.renderOrder = 3; me.castShadow = false;
  return me;
}
export function merge(geos) { return mergeGeometries(geos.map(g => g.index ? g.toNonIndexed() : g)); }
export function bend(geo, fn) { const p = geo.attributes.position, v = V3(); for (let i = 0; i < p.count; i++) { v.fromBufferAttribute(p, i); fn(v); p.setXYZ(i, v.x, v.y, v.z); } geo.computeVertexNormals(); return geo; }
// helix points
export function helix(r, pitch, turns, { n = 0, x0 = 0, axis = 'x' } = {}) {
  const N = n || Math.ceil(turns * 48), pts = [];
  for (let i = 0; i <= N; i++) {
    const a = (i / N) * turns * TAU, l = x0 + (i / N) * turns * pitch;
    pts.push(axis === 'x' ? V3(l, Math.cos(a) * r, Math.sin(a) * r) : axis === 'y' ? V3(Math.cos(a) * r, l, Math.sin(a) * r) : V3(Math.cos(a) * r, Math.sin(a) * r, l));
  }
  return pts;
}

/* ───────────────────────────── printing helpers ───────────────────────────── */
export const FONT = { sans: '"Lexend", "Inter", "DejaVu Sans", sans-serif', ui: '"Inter", "DejaVu Sans", sans-serif', mono: '"JetBrains Mono", "DejaVu Sans Mono", monospace' };
export function txt(g, s, x, y, { size = 20, weight = 700, color = '#111', align = 'left', base = 'alphabetic', font = FONT.sans, max = 0, spacing = 0 } = {}) {
  g.save();
  g.font = `${weight} ${size}px ${font}`;
  g.fillStyle = color; g.textAlign = align; g.textBaseline = base;
  if ('letterSpacing' in g) g.letterSpacing = `${spacing}px`;
  if (max) { const w = g.measureText(s).width; if (w > max) { g.translate(x, y); g.scale(max / w, 1); g.fillText(s, 0, 0); g.restore(); return; } }
  g.fillText(s, x, y);
  g.restore();
}
export function rr(g, x, y, w, h, r) { g.beginPath(); g.roundRect(x, y, w, h, r); }
export function barcode(g, x, y, w, h, seed = 3, color = '#111') {
  const R = rng(seed); let cx = x; g.fillStyle = color;
  while (cx < x + w - 3) { const bw = 1 + Math.floor(R() * 3.2); if (R() > 0.42) g.fillRect(cx, y, Math.min(bw, x + w - cx), h); cx += bw + 1; }
}
export function datamatrix(g, x, y, s, n = 14, seed = 5) {
  const R = rng(seed), c = s / n; g.fillStyle = '#111';
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) if (i === n - 1 || j === 0 || (i === 0 && j % 2 === 0) || (j === n - 1 && i % 2 === 1) || R() > 0.5) g.fillRect(x + j * c, y + i * c, c + 0.3, c + 0.3);
}
export function starOfLife(g, cx, cy, r, color = '#1f6fd1') {
  g.save(); g.translate(cx, cy); g.fillStyle = color;
  for (let k = 0; k < 3; k++) { g.save(); g.rotate(k * Math.PI / 3); rr(g, -r * 0.22, -r, r * 0.44, r * 2, r * 0.06); g.fill(); g.restore(); }
  g.strokeStyle = '#fff'; g.lineWidth = r * 0.08; g.beginPath(); g.moveTo(0, -r * 0.75); g.lineTo(0, r * 0.75); g.stroke();
  g.beginPath(); for (let i = 0; i <= 20; i++) { const yy = -r * 0.55 + i / 20 * r * 1.2, xx = Math.sin(i / 20 * Math.PI * 3) * r * 0.16; i ? g.lineTo(xx, yy) : g.moveTo(xx, yy); } g.stroke();
  g.restore();
}
export function cross(g, cx, cy, s, color = '#d22') {
  g.fillStyle = color; const a = s * 0.32;
  rr(g, cx - a / 2, cy - s / 2, a, s, a * 0.12); g.fill(); rr(g, cx - s / 2, cy - a / 2, s, a, a * 0.12); g.fill();
}
// fine-print lines (fake text): rows of short grey bars
export function finePrint(g, x, y, w, rows, { h = 4, gap = 4, color = 'rgba(0,0,0,.45)', seed = 9 } = {}) {
  const R = rng(seed); g.fillStyle = color;
  for (let r = 0; r < rows; r++) { let cx = x; const end = x + w * (0.55 + R() * 0.45); while (cx < end) { const ww = 6 + R() * 26; g.fillRect(cx, y + r * (h + gap), Math.min(ww, end - cx), h); cx += ww + 4; } }
}
export function hexColor(c) { return '#' + new THREE.Color(c).getHexString(); }
