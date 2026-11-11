/**
 * three.js scene of BrandLogo3D (lazy chunk: imported only by BrandLogo3D, so three is never part
 * of the main bundle). A chrome brand emblem turning slowly in a small studio: gradient dome +
 * soft boxes as the reflection environment, key / rim lights, transparent background.
 * The same studio set-up renders the 2D badges (tools/brand-badges.mjs).
 */
import {
  ACESFilmicToneMapping,
  BackSide,
  Box3,
  Color,
  DirectionalLight,
  DoubleSide,
  Float32BufferAttribute,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  PMREMGenerator,
  Scene,
  SphereGeometry,
  SRGBColorSpace,
  Vector3,
  WebGLRenderer,
  type Material,
  type Object3D,
  type Texture,
} from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/examples/jsm/libs/meshopt_decoder.module.js';

export interface BrandScene {
  /** draw size in CSS pixels (square) */
  resize(px: number): void;
  setSpinning(on: boolean): void;
  dispose(): void;
}

const SPIN = 0.55; // rad / s: one turn in about 11 s

function studio(renderer: WebGLRenderer): Texture {
  const s = new Scene();
  const geo = new SphereGeometry(10, 48, 24);
  const pos = geo.attributes.position;
  const col: number[] = [];
  for (let i = 0; i < pos.count; i++) {
    const t = (pos.getY(i) / 10 + 1) / 2;
    const c = 0.03 + 0.55 * Math.pow(t, 1.7);
    col.push(c, c, c * 1.03);
  }
  geo.setAttribute('color', new Float32BufferAttribute(col, 3));
  s.add(new Mesh(geo, new MeshBasicMaterial({ vertexColors: true, side: BackSide })));
  const panel = (w: number, h: number, x: number, y: number, z: number, k: number, hex: string) => {
    const m = new Mesh(new PlaneGeometry(w, h), new MeshBasicMaterial({ color: new Color(hex).multiplyScalar(k), side: DoubleSide }));
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
  const pmrem = new PMREMGenerator(renderer);
  const tex = pmrem.fromScene(s, 0.015).texture;
  pmrem.dispose();
  s.traverse((o) => {
    if (o instanceof Mesh) {
      o.geometry.dispose();
      (o.material as Material).dispose();
    }
  });
  return tex;
}

let loader: GLTFLoader | null = null;
function gltfLoader(): GLTFLoader {
  if (!loader) {
    loader = new GLTFLoader();
    loader.setMeshoptDecoder(MeshoptDecoder);
  }
  return loader;
}

/** Throws when WebGL is unavailable or the model cannot be loaded (the caller shows the badge). */
export async function createBrandScene(canvas: HTMLCanvasElement, url: string, px: number): Promise<BrandScene> {
  const renderer = new WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.25;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(px, px, false);

  let gltf;
  try {
    gltf = await gltfLoader().loadAsync(url);
  } catch (e) {
    renderer.dispose();
    throw e;
  }
  const env = studio(renderer);
  const scene = new Scene();
  scene.environment = env;
  const key = new DirectionalLight(0xffffff, 1.6);
  key.position.set(-1.5, 2, 3);
  const rim = new DirectionalLight(0x9fe8e0, 0.7);
  rim.position.set(2, -1, 1.5);
  scene.add(key, rim);

  const model: Object3D = gltf.scene;
  model.traverse((o) => {
    if (o instanceof Mesh && o.material instanceof MeshStandardMaterial) {
      o.material.envMapIntensity = 1.4;
      o.material.metalness = Math.max(o.material.metalness ?? 1, 0.95);
      o.material.roughness = Math.min(Math.max(o.material.roughness ?? 0.12, 0.12), 0.32);
    }
  });
  // centre the emblem on a pivot that turns around Y, with a slight forward tilt
  const box = new Box3().setFromObject(model);
  const size = box.getSize(new Vector3());
  model.position.sub(box.getCenter(new Vector3()));
  const pivot = new Group();
  pivot.add(model);
  pivot.rotation.x = 0.12;
  scene.add(pivot);

  const span = Math.max(size.x, size.y, size.z) * 1.12;
  const fov = 24;
  const dist = span / 2 / Math.tan(((fov / 2) * Math.PI) / 180) + Math.max(size.x, size.z) / 2;
  const camera = new PerspectiveCamera(fov, 1, dist / 50, dist * 4);
  camera.position.set(0, 0, dist);
  camera.lookAt(0, 0, 0);

  let spinning = true;
  let raf = 0;
  let last = performance.now();
  let disposed = false;
  pivot.rotation.y = -0.4;

  const frame = (t: number) => {
    raf = 0;
    if (disposed) return;
    const dt = Math.min((t - last) / 1000, 0.1);
    last = t;
    if (spinning) pivot.rotation.y += dt * SPIN;
    renderer.render(scene, camera);
    if (spinning) raf = requestAnimationFrame(frame);
  };
  const kick = () => {
    if (!raf && !disposed) {
      last = performance.now();
      raf = requestAnimationFrame(frame);
    }
  };
  kick();

  return {
    resize(next: number) {
      renderer.setSize(next, next, false);
      kick();
    },
    setSpinning(on: boolean) {
      spinning = on;
      kick();
    },
    dispose() {
      disposed = true;
      if (raf) cancelAnimationFrame(raf);
      scene.traverse((o) => {
        if (o instanceof Mesh) {
          o.geometry.dispose();
          const mats = Array.isArray(o.material) ? o.material : [o.material];
          mats.forEach((m: Material) => {
            Object.values(m).forEach((v) => {
              if (v && typeof v === 'object' && 'isTexture' in v) (v as Texture).dispose();
            });
            m.dispose();
          });
        }
      });
      env.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    },
  };
}
