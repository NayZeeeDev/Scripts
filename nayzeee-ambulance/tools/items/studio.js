// Product-shot studio for the item / tool-belt renders (driven by render.mjs).
// window.renderModel(set, name) → { size, data } : premultiplied RGBA, top row first, base64.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { HorizontalBlurShader } from 'three/addons/shaders/HorizontalBlurShader.js';
import { VerticalBlurShader } from 'three/addons/shaders/VerticalBlurShader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { ITEMS } from './models/items.js';
import { TOOLS } from './models/tools.js';

const SIZE = 1024;
const SETS = { items: ITEMS, tools: TOOLS };

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, premultipliedAlpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(SIZE, SIZE);
renderer.setClearColor(0x000000, 0);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.035).texture;
scene.environmentIntensity = 0.85;

// key (warm, upper left front), fill (cool, right), rim (behind, top), soft sky
const key = new THREE.DirectionalLight(0xfff0de, 2.4);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.bias = -0.0002;
key.shadow.normalBias = 0.02;
key.shadow.radius = 3;
const fill = new THREE.DirectionalLight(0xdce8ff, 0.75);
const rim = new THREE.DirectionalLight(0xffffff, 2.1);
const rim2 = new THREE.DirectionalLight(0xcfe3ff, 0.9);
const sky = new THREE.HemisphereLight(0xf4f7ff, 0x3a3530, 0.35);
scene.add(key, key.target, fill, fill.target, rim, rim.target, rim2, rim2.target, sky);

/* ── contact shadow (three.js webgl_shadow_contact technique): depth from below, blurred ── */
const CS = 512;
const shadowGroup = new THREE.Group();
scene.add(shadowGroup);
const rtA = new THREE.WebGLRenderTarget(CS, CS), rtB = new THREE.WebGLRenderTarget(CS, CS), rtWide = new THREE.WebGLRenderTarget(CS, CS);
[rtA, rtB, rtWide].forEach(r => { r.texture.generateMipmaps = false; });
const planeGeo = new THREE.PlaneGeometry(1, 1).rotateX(Math.PI / 2);
const tightMat = new THREE.MeshBasicMaterial({ map: rtA.texture, transparent: true, depthWrite: false, opacity: 0.9 });
const wideMat = new THREE.MeshBasicMaterial({ map: rtWide.texture, transparent: true, depthWrite: false, opacity: 0.55 });
const tightPlane = new THREE.Mesh(planeGeo, tightMat); tightPlane.scale.y = -1; tightPlane.renderOrder = 1;
const widePlane = new THREE.Mesh(planeGeo, wideMat); widePlane.scale.y = -1; widePlane.renderOrder = 0; widePlane.position.y = -0.001;
shadowGroup.add(tightPlane, widePlane);
const blurPlane = new THREE.Mesh(planeGeo); blurPlane.visible = false; shadowGroup.add(blurPlane);
const shadowCam = new THREE.OrthographicCamera(-0.5, 0.5, 0.5, -0.5, 0, 1);
shadowCam.rotation.x = Math.PI / 2;
shadowGroup.add(shadowCam);
const depthMat = new THREE.MeshDepthMaterial();
depthMat.userData.darkness = { value: 1.0 };
depthMat.onBeforeCompile = sh => {
  sh.uniforms.darkness = depthMat.userData.darkness;
  sh.fragmentShader = 'uniform float darkness;\n' + sh.fragmentShader.replace('gl_FragColor = vec4( vec3( 1.0 - fragCoordZ ), opacity );', 'gl_FragColor = vec4( vec3( 0.0 ), pow( 1.0 - fragCoordZ, 1.6 ) * darkness );');
};
depthMat.depthTest = false; depthMat.depthWrite = false; depthMat.side = THREE.DoubleSide;
const hBlur = new THREE.ShaderMaterial(HorizontalBlurShader); hBlur.depthTest = false;
const vBlur = new THREE.ShaderMaterial(VerticalBlurShader); vBlur.depthTest = false;
function blur(src, tmp, dst, amount) {
  blurPlane.visible = true;
  blurPlane.material = hBlur; hBlur.uniforms.tDiffuse.value = src.texture; hBlur.uniforms.h.value = amount / 256;
  renderer.setRenderTarget(tmp); renderer.render(blurPlane, shadowCam);
  blurPlane.material = vBlur; vBlur.uniforms.tDiffuse.value = tmp.texture; vBlur.uniforms.v.value = amount / 256;
  renderer.setRenderTarget(dst); renderer.render(blurPlane, shadowCam);
  blurPlane.visible = false;
}
function bakeContactShadow(root, box, o) {
  const ext = box.getSize(new THREE.Vector3()), c = box.getCenter(new THREE.Vector3());
  const span = Math.max(ext.x, ext.z) * (o.shadowSpan || 1.5) + ext.y * 0.3;
  shadowGroup.position.set(c.x, box.min.y + 0.002 * span, c.z);
  tightPlane.scale.set(span, -1, span); widePlane.scale.set(span, -1, span);
  shadowCam.left = shadowCam.bottom = -span / 2; shadowCam.right = shadowCam.top = span / 2;
  const reach = Math.max(Math.min(ext.y, Math.max(ext.x, ext.z) * 0.6), span * 0.05) * (o.shadowReach || 1);
  shadowCam.far = reach;
  shadowCam.updateProjectionMatrix();
  tightPlane.visible = widePlane.visible = false;
  const hidden = [];
  root.traverse(m => { if (m.isMesh && m.userData.noShadow && m.visible) { m.visible = false; hidden.push(m); } });
  scene.overrideMaterial = depthMat;
  depthMat.userData.darkness.value = o.shadowDark ?? 1.15;
  renderer.setClearColor(0x000000, 0);
  renderer.setRenderTarget(rtA); renderer.clear(); renderer.render(scene, shadowCam);
  scene.overrideMaterial = null;
  hidden.forEach(m => { m.visible = true; });
  // wide: heavy blur of the raw depth; tight: light blur
  blur(rtA, rtB, rtWide, 3.0); blur(rtWide, rtB, rtWide, 2.0); blur(rtWide, rtB, rtWide, 1.2);
  blur(rtA, rtB, rtA, 0.9); blur(rtA, rtB, rtA, 0.45);
  renderer.setRenderTarget(null);
  tightMat.opacity = o.shadowTight ?? 0.8;
  wideMat.opacity = o.shadowWide ?? 0.5;
  tightPlane.visible = widePlane.visible = o.shadow !== false;
}

/* ── framing ── */
const cam = new THREE.PerspectiveCamera(22, 1, 0.1, 5000);
const _v = new THREE.Vector3();
function projectedBounds(root, camera, floorY = null, grow = 1.04) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const take = v => { v.project(camera); x0 = Math.min(x0, v.x); x1 = Math.max(x1, v.x); y0 = Math.min(y0, v.y); y1 = Math.max(y1, v.y); };
  const c = root.userData.center || new THREE.Vector3();
  root.traverse(o => {
    if (!o.isMesh || !o.visible || o.userData.noFit) return;
    const p = o.geometry.attributes.position, step = Math.max(1, Math.floor(p.count / 40000));
    for (let i = 0; i < p.count; i += step) {
      _v.fromBufferAttribute(p, i).applyMatrix4(o.matrixWorld);
      const fx = _v.x, fz = _v.z;
      take(_v);
      // the vertex dropped onto the floor, pushed out a little: the contact-shadow footprint
      if (floorY !== null) take(_v.set(c.x + (fx - c.x) * grow, floorY, c.z + (fz - c.z) * grow));
    }
  });
  return { x0, y0, x1, y1 };
}
function frame(root, box, o) {
  const c = box.getCenter(new THREE.Vector3()), R = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 0.01);
  const elev = THREE.MathUtils.degToRad(o.elev ?? 30), az = THREE.MathUtils.degToRad(o.az ?? 0);
  const dir = new THREE.Vector3(Math.sin(az) * Math.cos(elev), Math.sin(elev), Math.cos(az) * Math.cos(elev));
  cam.fov = o.fov ?? 22;
  const dist = R / Math.sin(THREE.MathUtils.degToRad(cam.fov / 2)) * 1.05;
  cam.near = dist * 0.05; cam.far = dist * 4;
  cam.position.copy(c).addScaledVector(dir, dist);
  cam.up.set(0, 1, 0);
  cam.lookAt(c);
  cam.clearViewOffset(); cam.updateProjectionMatrix(); cam.updateMatrixWorld();
  root.userData.center = c;
  const b = projectedBounds(root, cam, o.shadow === false ? null : box.min.y, o.footGrow ?? 1.04);
  const w = b.x1 - b.x0, h = b.y1 - b.y0, fillTo = o.fill ?? 0.8;
  const k = (fillTo * 2) / Math.max(w, h);
  const cx = (b.x0 + b.x1) / 2 + (o.dx || 0), cy = (b.y0 + b.y1) / 2 + (o.dy || 0);
  const sw = SIZE / k;
  cam.setViewOffset(SIZE, SIZE, (cx + 1) / 2 * SIZE - sw / 2, (1 - cy) / 2 * SIZE - sw / 2, sw, sw);
  cam.updateProjectionMatrix();
  // lights relative to the camera
  const fwd = c.clone().sub(cam.position).normalize(), right = new THREE.Vector3().crossVectors(fwd, cam.up).normalize(), up = new THREE.Vector3().crossVectors(right, fwd).normalize();
  const place = (l, r_, u_, f_, s = 6) => { l.position.copy(c).addScaledVector(right, r_ * R * s).addScaledVector(up, u_ * R * s).addScaledVector(fwd, f_ * R * s); l.target.position.copy(c); };
  place(key, -0.75, 1.15, -0.55);
  place(fill, 1.0, 0.25, -0.5);
  place(rim, 0.55, 0.9, 1.0);
  place(rim2, -0.9, 0.35, 0.8);
  key.intensity = 2.4 * (o.key ?? 1); fill.intensity = 0.75 * (o.fillLight ?? 1); rim.intensity = 2.1 * (o.rim ?? 1); rim2.intensity = 0.9 * (o.rim ?? 1);
  scene.environmentIntensity = 0.85 * (o.env ?? 1);
  renderer.toneMappingExposure = o.exposure ?? 1.0;
  const sc = key.shadow.camera;
  sc.left = sc.bottom = -R * 1.3; sc.right = sc.top = R * 1.3; sc.near = R * 0.5; sc.far = R * 14;
  sc.updateProjectionMatrix();
}

/* ── glb (props pipeline exports, GTA axes) ── */
const loader = new GLTFLoader();
const glbCache = new Map();
export async function loadGLB(name) {
  if (!glbCache.has(name)) glbCache.set(name, loader.loadAsync(`/glb/${encodeURIComponent(name)}`));
  const g = await glbCache.get(name);
  const root = g.scene.clone(true);
  root.traverse(o => {
    if (!o.isMesh) return;
    o.castShadow = true; o.receiveShadow = true;
    const m = o.material;
    [m.map, m.normalMap, m.roughnessMap, m.metalnessMap].forEach(t => { if (t) t.anisotropy = 8; });
    if (m.transparent) { m.depthWrite = false; o.renderOrder = 2; o.castShadow = false; }
  });
  // centimetres + face the camera (+Z)
  const wrap = new THREE.Group();
  root.scale.setScalar(100);
  root.rotation.y = Math.PI;
  wrap.add(root);
  return wrap;
}
window.__nzLoadGLB = loadGLB;

/* ── render one model ── */
function disposeTree(root) {
  root.traverse(o => {
    if (!o.isMesh) return;
    o.geometry.dispose();
    (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => {
      for (const k of ['map', 'normalMap', 'roughnessMap', 'metalnessMap', 'alphaMap', 'emissiveMap', 'clearcoatNormalMap']) if (m[k] && !m[k].userData.keep) m[k].dispose();
      m.dispose();
    });
  });
}
window.listModels = set => Object.keys(SETS[set] || {});
window.renderModel = async (set, name) => {
  const def = SETS[set][name];
  if (!def) throw new Error(`unknown model ${set}/${name}`);
  const spec = typeof def === 'function' ? { build: def } : def;
  const o = Object.assign({}, spec.view || {});
  let root = await spec.build({ loadGLB });
  const holder = new THREE.Group();
  holder.add(root);
  // rest on y = 0
  holder.updateMatrixWorld(true);
  let box = new THREE.Box3().setFromObject(holder, true);
  holder.position.y -= box.min.y;
  holder.updateMatrixWorld(true);
  box = new THREE.Box3().setFromObject(holder, true);
  scene.add(holder);
  bakeContactShadow(holder, box, o);
  frame(holder, box, o);
  renderer.setRenderTarget(null);
  renderer.setClearColor(0x000000, 0);
  renderer.clear();
  renderer.render(scene, cam);
  const gl = renderer.getContext();
  const px = new Uint8Array(SIZE * SIZE * 4);
  gl.readPixels(0, 0, SIZE, SIZE, gl.RGBA, gl.UNSIGNED_BYTE, px);
  scene.remove(holder);
  disposeTree(holder);
  // flip to top-down + base64
  const row = SIZE * 4, out = new Uint8Array(px.length);
  for (let y = 0; y < SIZE; y++) out.set(px.subarray((SIZE - 1 - y) * row, (SIZE - y) * row), y * row);
  let bin = '';
  for (let i = 0; i < out.length; i += 0x8000) bin += String.fromCharCode.apply(null, out.subarray(i, i + 0x8000));
  return { size: SIZE, data: btoa(bin) };
};

await Promise.all(['400', '600', '700', '800'].map(w => document.fonts.load(`${w} 32px Lexend`))).catch(() => {});
await document.fonts.load('700 32px "JetBrains Mono"').catch(() => {});
window.__ready = true;
