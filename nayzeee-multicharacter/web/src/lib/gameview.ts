/*
  Frozen game frame for seamless scene changes.

  FiveM exposes the game's rendered frame to NUI WebGL: a texture whose WRAP_T is set to the
  CFX_BIND_GAME_VIEW constant (newer clients) or to the legacy MIRRORED_REPEAT -> REPEAT -> CLAMP_TO_EDGE
  sequence (older clients) samples the live game view instead of its own pixels. We draw ONE frame of it
  into a full-screen canvas, which then sits over the game while Lua rebuilds the scene underneath, and
  crossfade it away afterwards. Outside FiveM (browser preview) this simply reports "unsupported".
*/

type GL = WebGLRenderingContext & { CFX_BIND_GAME_VIEW?: number };

let canvas: HTMLCanvasElement | null = null;
let gl: GL | null = null;
let failed = false;

const VS = `attribute vec2 p; attribute vec2 t; varying vec2 v;
void main() { v = t; gl_Position = vec4(p, 0.0, 1.0); }`;
const FS = `precision mediump float; varying vec2 v; uniform sampler2D s;
void main() { gl_FragColor = texture2D(s, v); }`;

function shader(g: GL, type: number, src: string) {
  const sh = g.createShader(type)!;
  g.shaderSource(sh, src);
  g.compileShader(sh);
  return g.getShaderParameter(sh, g.COMPILE_STATUS) ? sh : null;
}

function setup(c: HTMLCanvasElement): boolean {
  if (gl) return true;
  if (failed || typeof (window as any).GetParentResourceName !== 'function') return false;
  const g = c.getContext('webgl', { alpha: false, antialias: false, depth: false, stencil: false, preserveDrawingBuffer: true }) as GL | null;
  if (!g) { failed = true; return false; }
  const vs = shader(g, g.VERTEX_SHADER, VS);
  const fs = shader(g, g.FRAGMENT_SHADER, FS);
  if (!vs || !fs) { failed = true; return false; }
  const prog = g.createProgram()!;
  g.attachShader(prog, vs); g.attachShader(prog, fs); g.linkProgram(prog);
  if (!g.getProgramParameter(prog, g.LINK_STATUS)) { failed = true; return false; }
  g.useProgram(prog);

  const tex = g.createTexture();
  g.bindTexture(g.TEXTURE_2D, tex);
  // Sentinel: if the game-view bind silently fails we sample this pure blue pixel and can detect it
  g.texImage2D(g.TEXTURE_2D, 0, g.RGBA, 1, 1, 0, g.RGBA, g.UNSIGNED_BYTE, new Uint8Array([0, 0, 255, 255]));
  g.texParameteri(g.TEXTURE_2D, g.TEXTURE_MIN_FILTER, g.LINEAR);
  g.texParameteri(g.TEXTURE_2D, g.TEXTURE_MAG_FILTER, g.LINEAR);
  g.texParameteri(g.TEXTURE_2D, g.TEXTURE_WRAP_S, g.CLAMP_TO_EDGE);
  const modern = g.CFX_BIND_GAME_VIEW !== undefined;
  if (modern) {
    g.texParameterf(g.TEXTURE_2D, g.TEXTURE_WRAP_T, g.CFX_BIND_GAME_VIEW!);
    g.texParameterf(g.TEXTURE_2D, g.TEXTURE_WRAP_T, g.CLAMP_TO_EDGE);
  } else {
    g.texParameterf(g.TEXTURE_2D, g.TEXTURE_WRAP_T, g.MIRRORED_REPEAT);
    g.texParameterf(g.TEXTURE_2D, g.TEXTURE_WRAP_T, g.REPEAT);
    g.texParameterf(g.TEXTURE_2D, g.TEXTURE_WRAP_T, g.CLAMP_TO_EDGE);
  }

  const quad = (loc: number, data: number[]) => {
    const b = g.createBuffer();
    g.bindBuffer(g.ARRAY_BUFFER, b);
    g.bufferData(g.ARRAY_BUFFER, new Float32Array(data), g.STATIC_DRAW);
    g.enableVertexAttribArray(loc);
    g.vertexAttribPointer(loc, 2, g.FLOAT, false, 0, 0);
  };
  quad(g.getAttribLocation(prog, 'p'), [-1, -1, 1, -1, -1, 1, 1, 1]);
  // The two binding paths deliver the frame with opposite vertical orientation
  quad(g.getAttribLocation(prog, 't'), modern ? [0, 1, 1, 1, 0, 0, 1, 0] : [0, 0, 1, 0, 0, 1, 1, 1]);
  g.uniform1i(g.getUniformLocation(prog, 's'), 0);

  c.addEventListener('webglcontextlost', (e) => { e.preventDefault(); gl = null; failed = true; });
  canvas = c;
  gl = g;
  return true;
}

// A real frame has some light in it and isn't our blue sentinel
function looksReal(g: GL, w: number, h: number) {
  const px = new Uint8Array(4);
  let lit = 0, blue = 0, n = 0;
  for (let i = 1; i <= 4; i++) for (let j = 1; j <= 4; j++) {
    g.readPixels(Math.floor((w * i) / 5), Math.floor((h * j) / 5), 1, 1, g.RGBA, g.UNSIGNED_BYTE, px);
    n++;
    if (px[0] + px[1] + px[2] > 24) lit++;
    if (px[0] < 8 && px[1] < 8 && px[2] > 247) blue++;
  }
  return lit >= 2 && blue < n;
}

/** Paint the current game frame into `c` (full window). Resolves false when unsupported / blank. */
export function captureFrame(c: HTMLCanvasElement): Promise<boolean> {
  if (!setup(c) || !gl) return Promise.resolve(false);
  const g = gl;
  return new Promise((resolve) => {
    requestAnimationFrame(() => {
      try {
        const w = Math.max(1, window.innerWidth), h = Math.max(1, window.innerHeight);
        if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
        g.viewport(0, 0, w, h);
        g.drawArrays(g.TRIANGLE_STRIP, 0, 4);
        g.flush();
        resolve(looksReal(g, w, h));
      } catch {
        resolve(false);
      }
    });
  });
}

/** Shrink the canvas back to 1px (frees the frame memory). */
export function releaseFrame() {
  if (canvas) { canvas.width = 1; canvas.height = 1; }
}
