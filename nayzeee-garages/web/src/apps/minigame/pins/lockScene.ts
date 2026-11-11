/**
 * The 3D pin tumbler lock (three.js, lazy chunk). A cutaway practice lock: a dark steel housing
 * with its front half removed and a tinted acrylic pin tower (teal edges, teal shear line), a
 * steel plug cut the same way, brass key pins, steel driver pins and springs, a hook pick that
 * levers on the keyway mouth and a top-of-keyway tension wrench with a teal grip.
 *
 * The scene only draws: model.ts owns the rules. frame() eases the drawn values toward the
 * model state and reports whether anything still moves, so the page renders only while needed.
 */
import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { LIFT_MAX, pinOffsets } from './model';
import type { LockState } from './model';

/* world units: plug radius 1 */
const SPACING = 0.9;
const RP = 1.0; // plug radius = shear line height
const RH = 1.38; // housing radius
const SHEAR = RP;
const KEYWAY = { bottom: -0.72, top: 0.3, half: 0.15 };
const KEY_BOTTOM = -0.3; // key pin body bottom at rest (its cone tip reaches into the keyway)
const CONE = 0.1;
const DRIVER = 0.6;
const CEIL = 3.0; // spring chamber ceiling
const TOWER_TOP = 3.2;
const LIFT_W = 0.78; // world units per lift unit
const PICK_Y = KEY_BOTTOM - CONE - 0.24; // pivot height: the hook tip touches the resting cone tip
const TENSION_DEG = 2.4;
const SET_DEG = 0.9;
const OPEN_DEG = 38;

export interface LockView {
  /** ease toward the state; returns true while something still moves */
  frame(state: LockState, dtMs: number): boolean;
  render(): void;
  resize(width: number, height: number): void;
  /** a shake (strength 0..1) */
  shake(strength: number): void;
  /** the pick snapped: the hook breaks off */
  snap(): void;
  dispose(): void;
}

class Helix extends THREE.Curve<THREE.Vector3> {
  constructor(private turns: number, private radius: number) {
    super();
  }
  getPoint(t: number, target = new THREE.Vector3()) {
    const a = t * this.turns * Math.PI * 2;
    return target.set(Math.cos(a) * this.radius, t, Math.sin(a) * this.radius);
  }
}

function cssColor(name: string, fallback: string): THREE.Color {
  const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  try {
    return new THREE.Color(raw || fallback);
  } catch {
    return new THREE.Color(fallback);
  }
}

const ease = (cur: number, target: number, dt: number, rate: number) => cur + (target - cur) * (1 - Math.exp(-dt * rate));

export function createLockView(canvas: HTMLCanvasElement, state: LockState): LockView {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const envTex = pmrem.fromScene(room, 0.04).texture;
  room.dispose();
  scene.environment = envTex;
  scene.environmentIntensity = 0.75;

  const teal = cssColor('--teal', '#08afa2');
  const tealHi = cssColor('--teal-hi', '#0fd4c4');

  /* ── materials ── */
  const steel = new THREE.MeshStandardMaterial({ color: 0xc3cbd0, metalness: 0.92, roughness: 0.3 });
  const plugSteel = new THREE.MeshStandardMaterial({ color: 0x9aa4aa, metalness: 0.9, roughness: 0.36 });
  const darkSteel = new THREE.MeshStandardMaterial({ color: 0x2b3135, metalness: 0.85, roughness: 0.48, side: THREE.DoubleSide });
  const bore = new THREE.MeshStandardMaterial({ color: 0x111517, metalness: 0.6, roughness: 0.7 });
  const brass = new THREE.MeshStandardMaterial({ color: 0xc8a052, metalness: 0.95, roughness: 0.28 });
  const springMat = new THREE.MeshStandardMaterial({ color: 0x9aa3a9, metalness: 0.95, roughness: 0.35 });
  const acrylic = new THREE.MeshStandardMaterial({
    color: 0x0c1719,
    metalness: 0.1,
    roughness: 0.12,
    transparent: true,
    opacity: 0.26,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  const edgeMat = new THREE.LineBasicMaterial({ color: teal, transparent: true, opacity: 0.55 });
  const rubber = new THREE.MeshStandardMaterial({ color: 0x16191b, metalness: 0.2, roughness: 0.75 });
  const tealMat = new THREE.MeshStandardMaterial({ color: teal, metalness: 0.35, roughness: 0.4, emissive: teal, emissiveIntensity: 0.18 });
  const shearMat = new THREE.MeshBasicMaterial({ color: tealHi, transparent: true, opacity: 0.55, depthWrite: false });
  const markerMat = new THREE.MeshBasicMaterial({ color: tealHi });

  const n = state.pins.length;
  const length = n * SPACING + 1.3;
  const x0 = -length / 2; // front face
  const pinX = (i: number) => x0 + 0.95 + i * SPACING;
  const towerX0 = pinX(0) - 0.52;
  const towerX1 = pinX(n - 1) + 0.52;

  const root = new THREE.Group();
  scene.add(root);
  const housing = new THREE.Group();
  root.add(housing);
  const plug = new THREE.Group();
  root.add(plug);

  /* ── housing: back half shell, rear cap, face ring, pin tower ── */
  const shellGeo = new THREE.CylinderGeometry(RH, RH, length, 56, 1, true, Math.PI / 2, Math.PI);
  shellGeo.rotateZ(Math.PI / 2);
  const shell = new THREE.Mesh(shellGeo, darkSteel);
  shell.position.x = x0 + length / 2;
  housing.add(shell);
  // the cut edges of the shell, in teal
  const cutPts = [
    new THREE.Vector3(x0, RH, 0.001), new THREE.Vector3(x0 + length, RH, 0.001),
    new THREE.Vector3(x0, -RH, 0.001), new THREE.Vector3(x0 + length, -RH, 0.001),
  ];
  housing.add(new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(cutPts), edgeMat));

  const rearGeo = new THREE.CircleGeometry(RH, 48, Math.PI / 2, Math.PI);
  rearGeo.rotateY(-Math.PI / 2);
  const rear = new THREE.Mesh(rearGeo, darkSteel);
  rear.position.x = x0 + length;
  housing.add(rear);

  const ringShape = new THREE.Shape();
  ringShape.absarc(0, 0, RH + 0.1, 0, Math.PI * 2, false);
  const ringHole = new THREE.Path();
  ringHole.absarc(0, 0, RP + 0.015, 0, Math.PI * 2, true);
  ringShape.holes.push(ringHole);
  const ringGeo = new THREE.ExtrudeGeometry(ringShape, { depth: 0.16, bevelEnabled: true, bevelSize: 0.04, bevelThickness: 0.04, bevelSegments: 2, curveSegments: 48 });
  ringGeo.rotateY(Math.PI / 2);
  const ring = new THREE.Mesh(ringGeo, steel);
  ring.position.x = x0 - 0.16;
  housing.add(ring);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(RH + 0.12, 0.025, 8, 72), tealMat);
  rim.rotation.y = Math.PI / 2;
  rim.position.x = x0 - 0.2;
  housing.add(rim);

  const towerH = TOWER_TOP - 0.55;
  const towerW = towerX1 - towerX0;
  const towerBack = new THREE.Mesh(new THREE.BoxGeometry(towerW, towerH, 0.45), darkSteel);
  towerBack.position.set((towerX0 + towerX1) / 2, 0.55 + towerH / 2, -0.225 - 0.001);
  housing.add(towerBack);
  const towerFront = new THREE.Mesh(new THREE.BoxGeometry(towerW, towerH, 0.9), acrylic);
  towerFront.position.set((towerX0 + towerX1) / 2, 0.55 + towerH / 2, 0);
  towerFront.renderOrder = 2;
  housing.add(towerFront);
  const towerEdges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(towerW, towerH, 0.9)), edgeMat);
  towerEdges.position.copy(towerFront.position);
  housing.add(towerEdges);
  // shear line on the acrylic
  const shear = new THREE.Mesh(new THREE.PlaneGeometry(towerW + 0.08, 0.028), shearMat);
  shear.position.set((towerX0 + towerX1) / 2, SHEAR, 0.452);
  shear.renderOrder = 3;
  housing.add(shear);

  // current pin marker above the tower
  const markerGeo = new THREE.ConeGeometry(0.11, 0.2, 3);
  markerGeo.rotateX(Math.PI);
  const marker = new THREE.Mesh(markerGeo, markerMat);
  marker.position.set(pinX(0), TOWER_TOP + 0.28, 0);
  housing.add(marker);

  /* ── plug: back half cut, keyway groove, face with the keyway ── */
  const half = new THREE.Shape();
  half.moveTo(0, RP);
  half.absarc(0, 0, RP, Math.PI / 2, -Math.PI / 2, true); // the x >= 0 half (world z <= 0 after the turn)
  half.lineTo(0, KEYWAY.bottom);
  half.lineTo(KEYWAY.half, KEYWAY.bottom);
  half.lineTo(KEYWAY.half, KEYWAY.top);
  half.lineTo(0, KEYWAY.top);
  half.lineTo(0, RP);
  const halfGeo = new THREE.ExtrudeGeometry(half, { depth: length, bevelEnabled: false, curveSegments: 40 });
  halfGeo.rotateY(Math.PI / 2); // extrude axis -> world +x, shape x -> world -z
  const plugBody = new THREE.Mesh(halfGeo, plugSteel);
  plugBody.position.x = x0;
  plug.add(plugBody);

  const faceShape = new THREE.Shape();
  faceShape.absarc(0, 0, RP, 0, Math.PI * 2, false);
  const keyHole = new THREE.Path();
  keyHole.moveTo(-KEYWAY.half, KEYWAY.bottom);
  keyHole.lineTo(-KEYWAY.half, KEYWAY.top);
  keyHole.lineTo(KEYWAY.half * 0.4, KEYWAY.top);
  keyHole.lineTo(KEYWAY.half, KEYWAY.top - 0.18);
  keyHole.lineTo(KEYWAY.half, KEYWAY.bottom);
  keyHole.lineTo(-KEYWAY.half, KEYWAY.bottom);
  faceShape.holes.push(keyHole);
  const faceGeo = new THREE.ExtrudeGeometry(faceShape, { depth: 0.12, bevelEnabled: true, bevelSize: 0.03, bevelThickness: 0.03, bevelSegments: 2, curveSegments: 48 });
  faceGeo.rotateY(Math.PI / 2);
  const face = new THREE.Mesh(faceGeo, steel);
  face.position.x = x0 - 0.12;
  plug.add(face);

  /* ── pins ── */
  const springGeo = new THREE.TubeGeometry(new Helix(9, 0.15), 180, 0.026, 6, false);
  const driverGeo = new THREE.CylinderGeometry(0.2, 0.2, DRIVER, 24);
  const keyPins: THREE.Group[] = [];
  const drivers: THREE.Mesh[] = [];
  const driverMats: THREE.MeshStandardMaterial[] = [];
  const springs: THREE.Mesh[] = [];
  const keyTop: number[] = [];
  state.pins.forEach((pin, i) => {
    const x = pinX(i);
    const top = SHEAR - pin.need * LIFT_W;
    keyTop[i] = top;
    const len = top - KEY_BOTTOM;
    const kp = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.19, 0.19, len, 24), brass);
    body.position.y = KEY_BOTTOM + len / 2;
    const tipGeo = new THREE.ConeGeometry(0.19, CONE, 24);
    tipGeo.rotateX(Math.PI);
    const tip = new THREE.Mesh(tipGeo, brass);
    tip.position.y = KEY_BOTTOM - CONE / 2;
    kp.add(body, tip);
    kp.position.x = x;
    plug.add(kp);
    keyPins.push(kp);

    const dm = steel.clone();
    dm.emissive = teal.clone();
    dm.emissiveIntensity = 0;
    driverMats.push(dm);
    const dp = new THREE.Mesh(driverGeo, dm);
    dp.position.set(x, top + DRIVER / 2, 0);
    housing.add(dp);
    drivers.push(dp);

    const sp = new THREE.Mesh(springGeo, springMat);
    sp.position.set(x, top + DRIVER, 0);
    sp.scale.y = CEIL - (top + DRIVER);
    housing.add(sp);
    springs.push(sp);

    const groove = new THREE.Mesh(new THREE.BoxGeometry(0.46, CEIL - 0.6, 0.02), bore);
    groove.position.set(x, 0.6 + (CEIL - 0.6) / 2, -0.012);
    housing.add(groove);
  });

  /* ── pick: pivots on the keyway mouth, slides between pins ── */
  const pickPivot = new THREE.Group();
  pickPivot.position.set(x0 - 0.02, PICK_Y, 0);
  root.add(pickPivot);
  const pickSlide = new THREE.Group();
  pickPivot.add(pickSlide);
  const shaftLen = pinX(n - 1) - x0 + 1.5;
  const shaftGeo = new THREE.BoxGeometry(shaftLen, 0.06, 0.045);
  shaftGeo.translate(-shaftLen / 2, 0, 0);
  pickSlide.add(new THREE.Mesh(shaftGeo, steel));
  const hook = new THREE.Group();
  const hookStem = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.22, 0.045), steel);
  hookStem.position.set(0.0, 0.11, 0);
  const hookLip = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.04, 0.045), steel);
  hookLip.position.set(0.03, 0.22, 0);
  hook.add(hookStem, hookLip);
  pickSlide.add(hook);
  const handleGeo = new THREE.CapsuleGeometry(0.13, 1.25, 6, 18);
  handleGeo.rotateZ(Math.PI / 2);
  const handle = new THREE.Mesh(handleGeo, rubber);
  handle.position.x = -shaftLen - 0.62;
  pickSlide.add(handle);
  const band = new THREE.Mesh(new THREE.CylinderGeometry(0.142, 0.142, 0.12, 24), tealMat);
  band.rotation.z = Math.PI / 2;
  band.position.x = -shaftLen - 0.12;
  pickSlide.add(band);

  /* ── tension wrench: in the top of the keyway, turns with the plug ── */
  const wrench = new THREE.Group();
  const legIn = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.05, 0.13), darkSteel);
  legIn.position.set(x0 + 0.08, KEYWAY.top - 0.06, 0);
  const legOut = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.05, 1.9), darkSteel);
  legOut.position.set(x0 - 0.16, KEYWAY.top - 0.06, 0.95);
  const grip = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.12, 0.85), tealMat);
  grip.position.set(x0 - 0.16, KEYWAY.top - 0.06, 1.45);
  wrench.add(legIn, legOut, grip);
  plug.add(wrench);

  /* ── lights ── */
  scene.add(new THREE.HemisphereLight(0xe6f2f5, 0x0c1012, 0.75));
  const key = new THREE.DirectionalLight(0xffffff, 1.7);
  key.position.set(-5, 9, 7);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xbfd8ff, 0.35);
  fill.position.set(6, 2, 5);
  scene.add(fill);
  const rimLight = new THREE.PointLight(teal, 5, 14, 1.6);
  rimLight.position.set(1.5, 2.2, -3.2);
  scene.add(rimLight);

  /* ── camera: front-left, a little above; fitted to the lock ── */
  const camera = new THREE.PerspectiveCamera(26, 1, 0.1, 100);
  const target = new THREE.Vector3((x0 - 2.2 + x0 + length) / 2, 1.0, 0.2);
  const dir = new THREE.Vector3(-0.5, 0.36, 0.86).normalize();
  const radius = Math.max((length + 2.6) / 2, 2.6) + 0.6;
  const fitDistance = (aspect: number) => {
    const vFov = THREE.MathUtils.degToRad(camera.fov);
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * aspect);
    return radius / Math.sin(Math.min(vFov, hFov) / 2);
  };
  const placeCamera = (aspect: number) => {
    camera.aspect = aspect;
    camera.position.copy(target).addScaledVector(dir, fitDistance(aspect));
    camera.lookAt(target);
    camera.updateProjectionMatrix();
  };
  placeCamera(1.35);

  /* ── drawn values (eased) ── */
  const shown = {
    key: state.pins.map(() => 0),
    driver: state.pins.map(() => 0),
    glow: state.pins.map(() => 0),
    pickX: pinX(state.pick),
    angle: 0,
    plug: 0,
    shear: 0.55,
  };
  let shakeAmp = 0;
  let shakeT = 0;
  let snapped: { vel: THREE.Vector3; spin: number; t: number } | null = null;

  const frame = (s: LockState, dtMs: number): boolean => {
    const dt = Math.min(0.05, dtMs / 1000);
    let moving = false;
    const close = (a: number, b: number, eps = 0.0005) => Math.abs(a - b) < eps;

    s.pins.forEach((p, i) => {
      const off = pinOffsets(p);
      const k = Math.min(LIFT_MAX, off.key) * LIFT_W;
      const d = Math.min(LIFT_MAX, off.driver) * LIFT_W;
      shown.key[i] = ease(shown.key[i], k, dt, 26);
      shown.driver[i] = ease(shown.driver[i], d, dt, 26);
      shown.glow[i] = ease(shown.glow[i], p.set ? 1 : 0, dt, 10);
      if (!close(shown.key[i], k) || !close(shown.driver[i], d) || !close(shown.glow[i], p.set ? 1 : 0, 0.01)) moving = true;
      keyPins[i].position.y = shown.key[i];
      // the driver rides on the key pin, unless set (held above the shear line)
      const driverLift = Math.max(shown.driver[i], p.set ? shown.driver[i] : shown.key[i]);
      drivers[i].position.y = keyTop[i] + DRIVER / 2 + driverLift;
      springs[i].position.y = keyTop[i] + DRIVER + driverLift;
      springs[i].scale.y = Math.max(0.12, CEIL - (keyTop[i] + DRIVER + driverLift));
      driverMats[i].emissiveIntensity = shown.glow[i] * 0.85;
      driverMats[i].color.setRGB(0.77 - shown.glow[i] * 0.25, 0.8, 0.82);
    });

    const px = pinX(s.pick);
    shown.pickX = ease(shown.pickX, px, dt, 18);
    if (!close(shown.pickX, px, 0.001)) moving = true;
    const d = Math.max(0.6, shown.pickX - pickPivot.position.x);
    pickSlide.position.x = d;
    const liftW = shown.key[s.pick];
    const want = Math.asin(Math.min(0.9, Math.max(0, liftW) / d));
    shown.angle = ease(shown.angle, want, dt, 30);
    if (!close(shown.angle, want, 0.0005)) moving = true;
    pickPivot.rotation.z = shown.angle;
    marker.position.x = shown.pickX;

    const plugTarget = s.status === 'open'
      ? OPEN_DEG
      : s.tension
        ? TENSION_DEG + s.setOrder.length * SET_DEG
        : 0;
    shown.plug = ease(shown.plug, plugTarget, dt, s.status === 'open' ? 5 : 16);
    if (!close(shown.plug, plugTarget, 0.02)) moving = true;
    plug.rotation.x = THREE.MathUtils.degToRad(shown.plug);
    tealMat.emissiveIntensity = s.tension || s.status === 'open' ? 0.55 : 0.18;

    const shearTarget = s.status === 'open' ? 1 : s.zone ? 1 : 0.55;
    shown.shear = ease(shown.shear, shearTarget, dt, 14);
    if (!close(shown.shear, shearTarget, 0.005)) moving = true;
    shearMat.opacity = shown.shear;

    // the pick trembles on the stiff binding pin while lifting
    let tremble = 0;
    if (s.lifting && s.status === 'play' && s.tension && s.order[s.setOrder.length] === s.pick && !s.pins[s.pick].set) {
      tremble = 0.006 + Math.min(1, s.speed / 1.4) * 0.012;
      moving = true;
    }
    if (shakeAmp > 0.0005) {
      shakeT += dt;
      shakeAmp *= Math.exp(-dt * 9);
      moving = true;
    } else {
      shakeAmp = 0;
    }
    const amp = shakeAmp + tremble;
    const now = performance.now() / 1000;
    root.position.set(Math.sin(now * 91) * amp, Math.sin(now * 113 + 1.3) * amp, 0);
    root.rotation.z = Math.sin(shakeT * 70) * shakeAmp * 0.25;

    if (snapped) {
      snapped.t += dt;
      snapped.vel.y -= 9.8 * dt * 0.6;
      hook.position.addScaledVector(snapped.vel, dt);
      hook.rotation.z += snapped.spin * dt;
      hook.rotation.x += snapped.spin * 0.6 * dt;
      if (snapped.t < 1.4) moving = true;
    }
    return moving;
  };

  const view: LockView = {
    frame,
    render: () => renderer.render(scene, camera),
    resize: (w, h) => {
      if (w <= 0 || h <= 0) return;
      renderer.setSize(w, h, false);
      placeCamera(w / h);
    },
    shake: (strength) => {
      shakeAmp = Math.max(shakeAmp, 0.03 * strength);
      shakeT = 0;
    },
    snap: () => {
      if (snapped) return;
      snapped = { vel: new THREE.Vector3(0.6, 1.4, 1.2), spin: 9, t: 0 };
      shakeAmp = 0.06;
      shakeT = 0;
    },
    dispose: () => {
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        if (mesh.geometry) mesh.geometry.dispose();
      });
      [steel, plugSteel, darkSteel, bore, brass, springMat, acrylic, edgeMat, rubber, tealMat, shearMat, markerMat, ...driverMats]
        .forEach((m) => m.dispose());
      envTex.dispose();
      pmrem.dispose();
      renderer.dispose();
    },
  };
  return view;
}
