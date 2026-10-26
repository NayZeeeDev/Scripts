// nayzeee product-shot renderer (WebGL2, hand written).
//
// Pipeline per job (all off-screen, the canvas is never shown):
//   1. load GLBs (glTF Y-up -> GTA Z-up), place instances, auto-frame the camera
//   2. studio environment: procedural soft boxes rendered to cube maps, GGX pre-filtered (split sum),
//      SH9 irradiance, DFG lookup table (cached between jobs)
//   3. phase 1 "visibility": many orthographic depth maps from a Fibonacci sphere of directions,
//      accumulated per pixel into ambient occlusion, a reflection-cone occlusion and the floor's sky visibility
//   4. phase 2 "lighting": N jittered frames (anti-aliasing), each with the three shadow-casting soft boxes
//      sampled at a new point of their area (soft shadows) -> HDR accumulation
//   5. bloom, tone mapping (AgX / ACES / Khronos neutral), sRGB, dither -> RGBA8 straight alpha
'use strict';

(function () {
  const SH = window.NZ_SHADERS;
  const D2R = Math.PI / 180;

  // ------------------------------------------------------------------ small vector / matrix kit
  const V = {
    add: (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
    sub: (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
    mul: (a, s) => [a[0] * s, a[1] * s, a[2] * s],
    dot: (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
    cross: (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
    len: (a) => Math.hypot(a[0], a[1], a[2]),
    norm: (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; },
  };
  // column-major 4x4
  const M = {
    ident() { const m = new Float32Array(16); m[0] = m[5] = m[10] = m[15] = 1; return m; },
    mul(a, b) {
      const o = new Float32Array(16);
      for (let c = 0; c < 4; c++)
        for (let r = 0; r < 4; r++) {
          let s = 0;
          for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
          o[c * 4 + r] = s;
        }
      return o;
    },
    translate(x, y, z) { const m = M.ident(); m[12] = x; m[13] = y; m[14] = z; return m; },
    scale(x, y, z) { const m = M.ident(); m[0] = x; m[5] = y; m[10] = z; return m; },
    rotX(d) { const m = M.ident(), c = Math.cos(d * D2R), s = Math.sin(d * D2R); m[5] = c; m[6] = s; m[9] = -s; m[10] = c; return m; },
    rotY(d) { const m = M.ident(), c = Math.cos(d * D2R), s = Math.sin(d * D2R); m[0] = c; m[2] = -s; m[8] = s; m[10] = c; return m; },
    rotZ(d) { const m = M.ident(), c = Math.cos(d * D2R), s = Math.sin(d * D2R); m[0] = c; m[1] = s; m[4] = -s; m[5] = c; return m; },
    fromQuat(q) {
      const [x, y, z, w] = q, m = M.ident();
      m[0] = 1 - 2 * (y * y + z * z); m[1] = 2 * (x * y + z * w); m[2] = 2 * (x * z - y * w);
      m[4] = 2 * (x * y - z * w); m[5] = 1 - 2 * (x * x + z * z); m[6] = 2 * (y * z + x * w);
      m[8] = 2 * (x * z + y * w); m[9] = 2 * (y * z - x * w); m[10] = 1 - 2 * (x * x + y * y);
      return m;
    },
    point(m, p) {
      return [m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
        m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]];
    },
    // inverse-transpose of the upper 3x3 (column-major Float32Array(9)) and the 3x3 determinant
    normal3(m) {
      const a = m[0], b = m[4], c = m[8], d = m[1], e = m[5], f = m[9], g = m[2], h = m[6], i = m[10];
      const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
      const det = a * A + b * B + c * C;
      const inv = 1 / (det || 1e-30);
      // cofactor matrix / det == inverse transpose; store column-major
      const o = new Float32Array(9);
      o[0] = A * inv; o[1] = -(b * i - c * h) * inv; o[2] = (b * f - c * e) * inv;
      o[3] = B * inv; o[4] = (a * i - c * g) * inv; o[5] = -(a * f - c * d) * inv;
      o[6] = C * inv; o[7] = -(a * h - b * g) * inv; o[8] = (a * e - b * d) * inv;
      // o currently holds the inverse in row-major order == the inverse transpose in column-major
      return { m: o, det };
    },
    ortho(l, r, b, t, n, f) {
      const m = new Float32Array(16);
      m[0] = 2 / (r - l); m[5] = 2 / (t - b); m[10] = -2 / (f - n);
      m[12] = -(r + l) / (r - l); m[13] = -(t + b) / (t - b); m[14] = -(f + n) / (f - n); m[15] = 1;
      return m;
    },
    perspective(fovy, aspect, n, f) {
      const t = 1 / Math.tan(fovy * D2R / 2), m = new Float32Array(16);
      m[0] = t / aspect; m[5] = t; m[10] = (f + n) / (n - f); m[11] = -1; m[14] = 2 * f * n / (n - f);
      return m;
    },
    // view matrix from an eye position and an orthonormal basis (right, up, forward)
    view(eye, r, u, f) {
      const m = new Float32Array(16);
      m[0] = r[0]; m[4] = r[1]; m[8] = r[2]; m[12] = -V.dot(r, eye);
      m[1] = u[0]; m[5] = u[1]; m[9] = u[2]; m[13] = -V.dot(u, eye);
      m[2] = -f[0]; m[6] = -f[1]; m[10] = -f[2]; m[14] = V.dot(f, eye);
      m[15] = 1;
      return m;
    },
  };
  // glTF (x, y, z) -> GTA (x, -z, y)
  const GLTF_TO_GTA = (() => { const m = M.ident(); m[5] = 0; m[6] = 1; m[9] = -1; m[10] = 0; return m; })();

  function trs(pos, rotDeg, scale) {
    // R = Rz * Ry * Rx (rotate about X first, then Y, then Z; all about the parent axes)
    let m = M.translate(pos[0], pos[1], pos[2]);
    m = M.mul(m, M.rotZ(rotDeg[2]));
    m = M.mul(m, M.rotY(rotDeg[1]));
    m = M.mul(m, M.rotX(rotDeg[0]));
    const s = Array.isArray(scale) ? scale : [scale, scale, scale];
    return M.mul(m, M.scale(s[0], s[1], s[2]));
  }

  const ANISO_SPP_ENV = 6;     // stochastic anisotropic samples per pixel per environment frame
  const ANISO_SPP_LIGHTS = 2;  // ... per soft-box frame

  // low-discrepancy sequences
  function halton(i, b) { let f = 1, r = 0; while (i > 0) { f /= b; r += f * (i % b); i = Math.floor(i / b); } return r; }
  function r2(i) { const g = 1.32471795724474602596; return [(0.5 + i / g) % 1, (0.5 + i / (g * g)) % 1]; }
  function tent(u) { return u < 0.5 ? Math.sqrt(2 * u) - 1 : 1 - Math.sqrt(2 - 2 * u); }

  // ------------------------------------------------------------------ studio rig (camera-relative)
  // Environment frame: +x = camera right, +y = horizontal direction toward the camera, +z = up.
  // az = degrees from +y toward +x (negative = camera left), el = degrees above the horizon.
  // w/h/r/soft are in gnomonic (tangent-plane) units around the box centre direction.
  // shadow: 0..2 = shadow-casting box, lit analytically with a shadow map (diffuse + reflection);
  // accent: true = small unshadowed light, lit analytically (max 2); otherwise baked into the environment map.
  const DEFAULT_RIG = {
    sky: { top: [0.030, 0.032, 0.035], horizon: [0.058, 0.058, 0.060], floorHorizon: [0.050, 0.048, 0.046], floorBottom: [0.018, 0.018, 0.018] },
    boxes: [
      { name: 'key', az: -46, el: 36, w: 0.46, h: 0.34, r: 0.10, soft: 0.07, L: 5.5, tint: [1.0, 0.975, 0.94], shadow: 0 },
      { name: 'fill', az: 64, el: 12, w: 0.62, h: 0.36, r: 0.12, soft: 0.10, L: 1.2, tint: [0.92, 0.96, 1.0], shadow: 1 },
      { name: 'rim', az: 148, el: 22, w: 0.12, h: 0.55, r: 0.05, soft: 0.04, L: 6.0, tint: [1.0, 1.0, 1.0], shadow: 2 },
      { name: 'strip', az: -150, el: 18, w: 0.09, h: 0.50, r: 0.04, soft: 0.04, L: 3.0, tint: [1.0, 1.0, 1.0], shadow: -1 },
      { name: 'top', az: 180, el: 76, w: 0.70, h: 0.60, r: 0.20, soft: 0.12, L: 1.4, tint: [1.0, 1.0, 1.0], shadow: -1 },
      { name: 'sweep', az: 180, el: 16, w: 1.10, h: 0.28, r: 0.20, soft: 0.15, L: 0.55, tint: [1.0, 1.0, 1.0], shadow: -1 },
      { name: 'kicker', az: 162, el: 34, w: 0.035, h: 0.035, r: 0.035, soft: 0.02, L: 60.0, tint: [1.0, 0.98, 0.95], shadow: -1, accent: true },
    ],
  };

  function boxBasis(b) {
    const az = b.az * D2R, el = b.el * D2R;
    const C = [Math.sin(az) * Math.cos(el), Math.cos(az) * Math.cos(el), Math.sin(el)];
    const U = V.norm(V.cross([0, 0, 1], C));
    const Vv = V.cross(C, U);
    return { C, U, V: Vv };
  }
  function smoothstep(a, b, x) { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); }
  // same profile as ENV_FS boxProfile, in gnomonic coordinates
  function boxProfile2(b, px, py) {
    const qx = Math.abs(px) - b.w + b.r, qy = Math.abs(py) - b.h + b.r;
    const sd = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - b.r;
    const edge = 1 - smoothstep(-b.soft, b.soft, sd);
    const nx = px / b.w, ny = py / b.h;
    return edge * (1 - 0.28 * Math.min(nx * nx + ny * ny, 1.5));
  }
  // Per-frame area-light samples for a shadow-casting box: direction (env frame) + irradiance weight.
  function boxSamples(b, frames, seed) {
    const bb = boxBasis(b);
    const hx = b.w + b.soft, hy = b.h + b.soft, area = 4 * hx * hy;
    const out = [];
    for (let f = 0; f < frames; f++) {
      const [u, v] = r2(f + seed);
      const px = (2 * u - 1) * hx, py = (2 * v - 1) * hy;
      const J = Math.pow(1 + px * px + py * py, -1.5);
      const w = boxProfile2(b, px, py) * J * area * b.L;
      const d = V.norm(V.add(bb.C, V.add(V.mul(bb.U, px), V.mul(bb.V, py))));
      out.push({ dir: d, E: [w * b.tint[0], w * b.tint[1], w * b.tint[2]] });
    }
    return out;
  }

  // ------------------------------------------------------------------ GL helpers
  class Prog {
    constructor(gl, vs, fs, name, defines = []) {
      this.gl = gl; this.name = name;
      const dl = defines.map((d) => `#define ${d}`).join('\n');
      vs = vs.replace('//DEFINES', dl);
      fs = fs.replace('//DEFINES', dl);
      const mk = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
          const log = gl.getShaderInfoLog(s);
          const lines = src.split('\n').map((l, i) => `${String(i + 1).padStart(4)}: ${l}`);
          const m = /ERROR: \d+:(\d+)/.exec(log || '');
          const at = m ? +m[1] : 0;
          const ctx = at ? lines.slice(Math.max(0, at - 4), at + 3).join('\n') : '';
          throw new Error(`shader ${name} (${type === gl.VERTEX_SHADER ? 'vs' : 'fs'}) failed:\n${log}\n${ctx}`);
        }
        return s;
      };
      const p = gl.createProgram();
      gl.attachShader(p, mk(gl.VERTEX_SHADER, vs));
      gl.attachShader(p, mk(gl.FRAGMENT_SHADER, fs));
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`program ${name} link failed: ${gl.getProgramInfoLog(p)}`);
      this.p = p;
      this.loc = new Map();
    }
    use() { this.gl.useProgram(this.p); return this; }
    u(n) { let l = this.loc.get(n); if (l === undefined) { l = this.gl.getUniformLocation(this.p, n); this.loc.set(n, l); } return l; }
    f1(n, v) { const l = this.u(n); if (l) this.gl.uniform1f(l, v); return this; }
    i1(n, v) { const l = this.u(n); if (l) this.gl.uniform1i(l, v); return this; }
    f2(n, a, b) { const l = this.u(n); if (l) this.gl.uniform2f(l, a, b); return this; }
    f3(n, v) { const l = this.u(n); if (l) this.gl.uniform3f(l, v[0], v[1], v[2]); return this; }
    f4(n, v) { const l = this.u(n); if (l) this.gl.uniform4f(l, v[0], v[1], v[2], v[3]); return this; }
    i4(n, v) { const l = this.u(n); if (l) this.gl.uniform4i(l, v[0], v[1], v[2], v[3]); return this; }
    f1v(n, v) { const l = this.u(n); if (l) this.gl.uniform1fv(l, v); return this; }
    f3v(n, v) { const l = this.u(n); if (l) this.gl.uniform3fv(l, v); return this; }
    m3(n, v) { const l = this.u(n); if (l) this.gl.uniformMatrix3fv(l, false, v); return this; }
    m4(n, v) { const l = this.u(n); if (l) this.gl.uniformMatrix4fv(l, false, v); return this; }
    m4v(n, v) { const l = this.u(n); if (l) this.gl.uniformMatrix4fv(l, false, v); return this; }
    m3t(n, v) { const l = this.u(n); if (l) this.gl.uniformMatrix3fv(l, false, v); return this; }
  }

  // ------------------------------------------------------------------ renderer
  class Renderer {
    constructor() {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 4;
      const gl = canvas.getContext('webgl2', {
        antialias: false, depth: false, stencil: false, alpha: true, premultipliedAlpha: false,
        preserveDrawingBuffer: false, powerPreference: 'high-performance',
      });
      if (!gl) throw new Error('WebGL2 is not available in this browser');
      for (const e of ['EXT_color_buffer_float', 'EXT_float_blend', 'OES_texture_float_linear'])
        if (!gl.getExtension(e)) throw new Error(`required WebGL extension missing: ${e}`);
      this.gl = gl;
      this.anisoExt = gl.getExtension('EXT_texture_filter_anisotropic');
      this.maxAniso = this.anisoExt ? gl.getParameter(this.anisoExt.MAX_TEXTURE_MAX_ANISOTROPY_EXT) : 1;
      const dbg = gl.getExtension('WEBGL_debug_renderer_info');
      this.gpu = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      const P = (vs, fs, n) => new Prog(gl, vs, fs, n);
      this.p = {
        env: P(SH.FULLSCREEN_VS, SH.ENV_FS, 'env'),
        prefilter: P(SH.FULLSCREEN_VS, SH.PREFILTER_FS, 'prefilter'),
        brdf: P(SH.FULLSCREEN_VS, SH.BRDF_LUT_FS, 'brdf'),
        depth: P(SH.DEPTH_VS, SH.DEPTH_FS, 'depth'),
        prepass: P(SH.MESH_VS, SH.DEPTH_FS, 'prepass'),
        aoFill: P(SH.FULLSCREEN_VS, SH.AO_FILL_FS, 'aoFill'),
        aoGround: P(SH.GROUND_VS, SH.AO_GROUND_FS, 'aoGround'),

        ground: P(SH.GROUND_VS, SH.GROUND_FS, 'ground'),
        copyAdd: P(SH.FULLSCREEN_VS, SH.COPY_ADD_FS, 'copyAdd'),
        bright: P(SH.FULLSCREEN_VS, SH.BRIGHT_FS, 'bright'),
        down: P(SH.FULLSCREEN_VS, SH.DOWN_FS, 'down'),
        blur: P(SH.FULLSCREEN_VS, SH.BLUR_FS, 'blur'),
        final: P(SH.FULLSCREEN_VS, SH.FINAL_FS, 'final'),
      };
      this.emptyVAO = gl.createVertexArray();
      this.white = this.tex2D(1, 1, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
      this.syncFB = this.fbo([this.tex2D(1, 1, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, null)], null);
      this.syncPx = new Uint8Array(4);
      this.samplers = new Map();
      this.variants = new Map();
      this.models = new Map();
      this.envCache = new Map();
      this.targets = null;
      this.brdf = null;
      this.groundVAO = null;
    }

    // shader variants (compile-time branches: SwiftShader runs both sides of dynamic branches)
    // kind: 'ao' (phase 1), 'env' / 'lights' (phase 2 environment / soft-box passes)
    variant(kind, mat, prim) {
      const defs = [];
      if (!prim.hasTangents) defs.push('NO_TANGENT');
      if (mat.alphaMode === 1) defs.push('ALPHA_MASK');
      if (kind !== 'ao') {
        if (kind === 'lights') defs.push('PASS_LIGHTS');
        if (mat.aniso && mat.aniso.strength > 0) defs.push('ANISO', `ANISO_SAMPLES ${kind === 'lights' ? ANISO_SPP_LIGHTS : ANISO_SPP_ENV}`);
      }
      const key = kind + '|' + defs.join(',');
      let p = this.variants.get(key);
      if (!p) {
        p = new Prog(this.gl, SH.MESH_VS, kind === 'ao' ? SH.AO_FS : SH.MAIN_FS, key, defs);
        this.variants.set(key, p);
      }
      return p;
    }

    // ---------------- textures / framebuffers
    tex2D(w, h, internal, format, type, data, opt = {}) {
      const gl = this.gl, t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texImage2D(gl.TEXTURE_2D, 0, internal, w, h, 0, format, type, data || null);
      const filt = opt.filter || gl.LINEAR;
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filt);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filt);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      t.w = w; t.h = h;
      return t;
    }
    fbo(colors, depth) {
      const gl = this.gl, f = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, f);
      const bufs = [];
      colors.forEach((t, i) => { gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + i, gl.TEXTURE_2D, t, 0); bufs.push(gl.COLOR_ATTACHMENT0 + i); });
      if (depth) gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth);
      gl.drawBuffers(bufs.length ? bufs : [gl.NONE]);
      const st = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
      if (st !== gl.FRAMEBUFFER_COMPLETE) throw new Error(`framebuffer incomplete: 0x${st.toString(16)}`);
      return f;
    }
    depthRB(w, h) {
      const gl = this.gl, rb = gl.createRenderbuffer();
      gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, w, h);
      return rb;
    }
    depthArray(size, layers) {
      const gl = this.gl, t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D_ARRAY, t);
      gl.texStorage3D(gl.TEXTURE_2D_ARRAY, 1, gl.DEPTH_COMPONENT24, size, size, layers);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
      gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL);
      const fb = gl.createFramebuffer();
      return { tex: t, fb, size, layers };
    }
    uploadImage(bitmap, srgb, sampler) {
      const gl = this.gl, t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
      gl.texImage2D(gl.TEXTURE_2D, 0, srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, bitmap);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      const wrap = (v) => (v === 33071 ? gl.CLAMP_TO_EDGE : v === 33648 ? gl.MIRRORED_REPEAT : gl.REPEAT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap(sampler && sampler.wrapS));
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap(sampler && sampler.wrapT));
      if (this.anisoExt) gl.texParameterf(gl.TEXTURE_2D, this.anisoExt.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(16, this.maxAniso));
      return t;
    }

    // ---------------- glTF binary loader
    async loadModel(url) {
      if (this.models.has(url)) return this.models.get(url);
      const res = await fetch(url);
      if (!res.ok) throw new Error(`cannot load ${url}: HTTP ${res.status}`);
      const model = await this.parseGLB(await res.arrayBuffer(), url);
      this.models.set(url, model);
      return model;
    }

    async parseGLB(buf, label) {
      const gl = this.gl, dv = new DataView(buf);
      if (buf.byteLength < 20 || dv.getUint32(0, true) !== 0x46546C67) throw new Error(`${label}: not a binary glTF (.glb)`);
      let off = 12, json = null, bin = null;
      while (off + 8 <= buf.byteLength) {
        const len = dv.getUint32(off, true), type = dv.getUint32(off + 4, true);
        if (type === 0x4E4F534A) json = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, off + 8, len)));
        else if (type === 0x004E4942) bin = new Uint8Array(buf, off + 8, len);
        off += 8 + len;
      }
      if (!json) throw new Error(`${label}: GLB has no JSON chunk`);
      const bitmaps = await Promise.all((json.images || []).map(async (im) => {
        let blob;
        if (im.bufferView !== undefined) {
          const bv = json.bufferViews[im.bufferView], o = bv.byteOffset || 0;
          blob = new Blob([bin.slice(o, o + bv.byteLength)], { type: im.mimeType || 'image/png' });
        } else if (im.uri && im.uri.startsWith('data:')) {
          blob = await (await fetch(im.uri)).blob();
        } else throw new Error(`${label}: external image uris are not supported`);
        return createImageBitmap(blob, { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
      }));
      const texCache = new Map();
      const getTex = (info, srgb) => {
        if (!info || info.index === undefined) return null;
        const t = json.textures[info.index];
        const key = `${t.source}|${srgb}|${t.sampler}`;
        if (!texCache.has(key)) {
          const smp = json.samplers && t.sampler !== undefined ? json.samplers[t.sampler] : null;
          texCache.set(key, this.uploadImage(bitmaps[t.source], srgb, smp));
        }
        return texCache.get(key);
      };
      const materials = (json.materials || []).map((m, i) => {
        const pbr = m.pbrMetallicRoughness || {};
        const ext = m.extensions || {};
        const es = ext.KHR_materials_emissive_strength ? ext.KHR_materials_emissive_strength.emissiveStrength : 1;
        const an = ext.KHR_materials_anisotropy;
        return {
          name: m.name || `material_${i}`,
          baseFactor: pbr.baseColorFactor || [1, 1, 1, 1],
          metallic: pbr.metallicFactor !== undefined ? pbr.metallicFactor : 1,
          roughness: pbr.roughnessFactor !== undefined ? pbr.roughnessFactor : 1,
          baseTex: getTex(pbr.baseColorTexture, true),
          mrTex: getTex(pbr.metallicRoughnessTexture, false),
          normalTex: getTex(m.normalTexture, false),
          normalScale: m.normalTexture && m.normalTexture.scale !== undefined ? m.normalTexture.scale : 1,
          occlTex: getTex(m.occlusionTexture, false),
          occlStrength: m.occlusionTexture && m.occlusionTexture.strength !== undefined ? m.occlusionTexture.strength : 1,
          emisTex: getTex(m.emissiveTexture, true),
          emissive: (m.emissiveFactor || [0, 0, 0]).map((c) => c * es),
          alphaMode: { OPAQUE: 0, MASK: 1, BLEND: 2 }[m.alphaMode || 'OPAQUE'],
          alphaCutoff: m.alphaCutoff !== undefined ? m.alphaCutoff : 0.5,
          doubleSided: !!m.doubleSided,
          aniso: an ? { mode: 'tangent', strength: an.anisotropyStrength || 0, roughness_across: 0.6 } : null,
        };
      });
      const defaultMat = {
        name: 'default', baseFactor: [0.8, 0.8, 0.8, 1], metallic: 0, roughness: 0.5, normalScale: 1, occlStrength: 1,
        emissive: [0, 0, 0], alphaMode: 0, alphaCutoff: 0.5, doubleSided: false, aniso: null,
      };
      const prims = [];
      const nodeMatrix = (n) => {
        if (n.matrix) return new Float32Array(n.matrix);
        let m = M.ident();
        if (n.translation) m = M.mul(m, M.translate(...n.translation));
        if (n.rotation) m = M.mul(m, M.fromQuat(n.rotation));
        if (n.scale) m = M.mul(m, M.scale(...n.scale));
        return m;
      };
      const visit = (ni, parent) => {
        const node = json.nodes[ni];
        const world = M.mul(parent, nodeMatrix(node));
        if (node.mesh !== undefined)
          for (const pr of json.meshes[node.mesh].primitives) {
            if (pr.mode !== undefined && pr.mode !== 4) continue;
            prims.push(this.buildPrim(json, bin, pr, world, pr.material !== undefined ? materials[pr.material] : defaultMat));
          }
        for (const c of node.children || []) visit(c, world);
      };
      const scene = json.scenes ? json.scenes[json.scene || 0] : { nodes: json.nodes.map((_, i) => i) };
      for (const n of scene.nodes) visit(n, GLTF_TO_GTA);
      if (!prims.length) throw new Error(`${label}: no triangle primitives`);
      let tris = 0;
      for (const p of prims) tris += p.count / 3;
      return { label, prims, materials, tris };
    }

    readAccessor(json, bin, idx) {
      const acc = json.accessors[idx];
      const n = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 }[acc.type];
      const TA = { 5120: Int8Array, 5121: Uint8Array, 5122: Int16Array, 5123: Uint16Array, 5125: Uint32Array, 5126: Float32Array }[acc.componentType];
      const out = new Float32Array(acc.count * n);
      if (acc.bufferView === undefined) return { data: out, n };
      const bv = json.bufferViews[acc.bufferView];
      const bpe = TA.BYTES_PER_ELEMENT;
      const stride = bv.byteStride || n * bpe;
      const base = bin.byteOffset + (bv.byteOffset || 0) + (acc.byteOffset || 0);
      const dv = new DataView(bin.buffer);
      const rd = {
        5120: (o) => dv.getInt8(o), 5121: (o) => dv.getUint8(o), 5122: (o) => dv.getInt16(o, true),
        5123: (o) => dv.getUint16(o, true), 5125: (o) => dv.getUint32(o, true), 5126: (o) => dv.getFloat32(o, true),
      }[acc.componentType];
      const norm = acc.normalized ? { 5120: 127, 5121: 255, 5122: 32767, 5123: 65535, 5125: 4294967295, 5126: 1 }[acc.componentType] : 1;
      for (let i = 0; i < acc.count; i++)
        for (let c = 0; c < n; c++) {
          let v = rd(base + i * stride + c * bpe);
          if (norm !== 1) v = Math.max(v / norm, -1);
          out[i * n + c] = v;
        }
      return { data: out, n };
    }

    buildPrim(json, bin, pr, world, material) {
      const gl = this.gl, A = pr.attributes;
      const pos = this.readAccessor(json, bin, A.POSITION).data;
      const vcount = pos.length / 3;
      let idx;
      if (pr.indices !== undefined) {
        const acc = json.accessors[pr.indices];
        const bv = json.bufferViews[acc.bufferView];
        const o = bin.byteOffset + (bv.byteOffset || 0) + (acc.byteOffset || 0);
        if (acc.componentType === 5125) idx = new Uint32Array(bin.buffer.slice(o, o + acc.count * 4));
        else if (acc.componentType === 5123) idx = Uint32Array.from(new Uint16Array(bin.buffer.slice(o, o + acc.count * 2)));
        else idx = Uint32Array.from(new Uint8Array(bin.buffer.slice(o, o + acc.count)));
      } else idx = Uint32Array.from({ length: vcount }, (_, i) => i);
      let nrm = A.NORMAL !== undefined ? this.readAccessor(json, bin, A.NORMAL).data : null;
      if (!nrm) {                                   // smooth normals from faces
        nrm = new Float32Array(vcount * 3);
        for (let t = 0; t < idx.length; t += 3) {
          const a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
          const e1 = [pos[b] - pos[a], pos[b + 1] - pos[a + 1], pos[b + 2] - pos[a + 2]];
          const e2 = [pos[c] - pos[a], pos[c + 1] - pos[a + 1], pos[c + 2] - pos[a + 2]];
          const fn = V.cross(e1, e2);
          for (const k of [a, b, c]) { nrm[k] += fn[0]; nrm[k + 1] += fn[1]; nrm[k + 2] += fn[2]; }
        }
      }
      const tan = A.TANGENT !== undefined ? this.readAccessor(json, bin, A.TANGENT).data : new Float32Array(vcount * 4);
      const uv = A.TEXCOORD_0 !== undefined ? this.readAccessor(json, bin, A.TEXCOORD_0).data : new Float32Array(vcount * 2);
      let col;
      if (A.COLOR_0 !== undefined) {
        const c = this.readAccessor(json, bin, A.COLOR_0);
        col = new Float32Array(vcount * 4);
        for (let i = 0; i < vcount; i++) {
          col[i * 4] = c.data[i * c.n]; col[i * 4 + 1] = c.data[i * c.n + 1]; col[i * 4 + 2] = c.data[i * c.n + 2];
          col[i * 4 + 3] = c.n === 4 ? c.data[i * c.n + 3] : 1;
        }
      } else col = new Float32Array(vcount * 4).fill(1);
      // bake the node transform (incl. glTF -> GTA axes) into the vertices
      const nm = M.normal3(world);
      const flip = nm.det < 0 ? -1 : 1;
      const P = new Float32Array(vcount * 3), N = new Float32Array(vcount * 3), T = new Float32Array(vcount * 4);
      let hasTangents = A.TANGENT !== undefined;
      const bmin = [Infinity, Infinity, Infinity], bmax = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i < vcount; i++) {
        const p = M.point(world, [pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]]);
        P.set(p, i * 3);
        for (let k = 0; k < 3; k++) { bmin[k] = Math.min(bmin[k], p[k]); bmax[k] = Math.max(bmax[k], p[k]); }
        const n0 = nrm[i * 3], n1 = nrm[i * 3 + 1], n2 = nrm[i * 3 + 2], m = nm.m;
        const nn = V.norm([m[0] * n0 + m[3] * n1 + m[6] * n2, m[1] * n0 + m[4] * n1 + m[7] * n2, m[2] * n0 + m[5] * n1 + m[8] * n2]);
        N.set(nn, i * 3);
        const t0 = tan[i * 4], t1 = tan[i * 4 + 1], t2 = tan[i * 4 + 2];
        if (t0 || t1 || t2) {
          const tt = V.norm([world[0] * t0 + world[4] * t1 + world[8] * t2, world[1] * t0 + world[5] * t1 + world[9] * t2,
            world[2] * t0 + world[6] * t1 + world[10] * t2]);
          T.set([tt[0], tt[1], tt[2], (tan[i * 4 + 3] || 1) * flip], i * 4);
        }
      }
      if (flip < 0) for (let t = 0; t < idx.length; t += 3) { const s = idx[t + 1]; idx[t + 1] = idx[t + 2]; idx[t + 2] = s; }
      const vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      const attr = (loc, data, size) => {
        const b = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, b);
        gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
        gl.enableVertexAttribArray(loc);
        gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
      };
      attr(0, P, 3); attr(1, N, 3); attr(2, T, 4); attr(3, uv, 2); attr(4, col, 4);
      const ib = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
      gl.bindVertexArray(null);
      // keep a vertex subset for framing / bounds
      const step = Math.max(1, Math.floor(vcount / 20000));
      const sample = [];
      for (let i = 0; i < vcount; i += step) sample.push(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]);
      return { vao, count: idx.length, material, points: new Float32Array(sample), bmin, bmax, hasTangents };
    }

    // ---------------- environment, SH, DFG
    ensureBRDF() {
      if (this.brdf) return this.brdf;
      const gl = this.gl, S = 128;
      const t = this.tex2D(S, S, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, null);
      const f = this.fbo([t], null);
      gl.viewport(0, 0, S, S);
      gl.disable(gl.DEPTH_TEST); gl.disable(gl.BLEND);
      this.p.brdf.use().f1('uSize', S);
      gl.bindVertexArray(this.emptyVAO);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.deleteFramebuffer(f);
      this.brdf = t;
      return t;
    }

    cube(size, levels) {
      const gl = this.gl, t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_CUBE_MAP, t);
      gl.texStorage2D(gl.TEXTURE_CUBE_MAP, levels, gl.RGBA16F, size, size);
      gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, levels > 1 ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      for (const w of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T, gl.TEXTURE_WRAP_R]) gl.texParameteri(gl.TEXTURE_CUBE_MAP, w, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, levels - 1);
      return t;
    }

    ensureEnv(rig) {
      const key = JSON.stringify(rig);
      if (this.envCache.has(key)) return this.envCache.get(key);
      const gl = this.gl;
      const RAW = 256, RAW_LEVELS = 9, PRE_LEVELS = 6;
      const fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.disable(gl.DEPTH_TEST); gl.disable(gl.BLEND); gl.disable(gl.CULL_FACE);
      gl.bindVertexArray(this.emptyVAO);
      const boxes = rig.boxes.map((b) => ({ ...b, ...boxBasis(b) }));
      const setBoxes = (p) => {
        const n = Math.min(boxes.length, 8);
        const C = [], U = [], Vv = [], Sz = [], L = [];
        for (let i = 0; i < 8; i++) {
          const b = boxes[i] || boxes[0];
          C.push(...b.C); U.push(...b.U); Vv.push(...b.V);
          Sz.push(b.w, b.h, b.r, b.soft);
          L.push(b.L * b.tint[0], b.L * b.tint[1], b.L * b.tint[2], b.shadow >= 0 || b.accent ? 1 : -1);
        }
        p.i1('uBoxCount', n);
        p.f3v('uBoxC', new Float32Array(C)); p.f3v('uBoxU', new Float32Array(U)); p.f3v('uBoxV', new Float32Array(Vv));
        const lS = p.u('uBoxS'); if (lS) gl.uniform4fv(lS, new Float32Array(Sz));
        const lL = p.u('uBoxL'); if (lL) gl.uniform4fv(lL, new Float32Array(L));
        p.f3('uSkyTop', rig.sky.top).f3('uSkyHorizon', rig.sky.horizon)
          .f3('uFloorHorizon', rig.sky.floorHorizon).f3('uFloorBottom', rig.sky.floorBottom);
      };
      const renderEnv = (tex) => {
        const p = this.p.env.use();
        setBoxes(p);
        p.f1('uSize', RAW);
        gl.viewport(0, 0, RAW, RAW);
        for (let f = 0; f < 6; f++) {
          gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_CUBE_MAP_POSITIVE_X + f, tex, 0);
          p.i1('uFace', f);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
        }
      };
      const env = { raw: [], pre: [], lods: PRE_LEVELS - 1, rawSize: RAW };
      {
        const raw = this.cube(RAW, RAW_LEVELS);
        renderEnv(raw);
        gl.bindTexture(gl.TEXTURE_CUBE_MAP, raw);
        gl.generateMipmap(gl.TEXTURE_CUBE_MAP);
        const pre = this.cube(RAW, PRE_LEVELS);
        renderEnv(pre);                           // level 0 = mirror
        const p = this.p.prefilter.use();
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_CUBE_MAP, raw);
        p.i1('uSrc', 0).f1('uSrcSize', RAW);
        for (let lv = 1; lv < PRE_LEVELS; lv++) {
          const sz = RAW >> lv;
          gl.viewport(0, 0, sz, sz);
          p.f1('uSize', sz).f1('uRough', lv / (PRE_LEVELS - 1)).i1('uSamples', lv === 1 ? 768 : 512);
          for (let f = 0; f < 6; f++) {
            gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_CUBE_MAP_POSITIVE_X + f, pre, lv);
            p.i1('uFace', f);
            gl.drawArrays(gl.TRIANGLES, 0, 3);
          }
        }
        env.raw.push(raw); env.pre.push(pre);
      }
      // SH9 irradiance of env A (read back the 32x32 mip of the raw cube)
      const lvl = 3, S = RAW >> lvl, px = new Float32Array(S * S * 4);
      const sh = Array.from({ length: 9 }, () => [0, 0, 0]);
      for (let f = 0; f < 6; f++) {
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_CUBE_MAP_POSITIVE_X + f, env.raw[0], lvl);
        gl.readPixels(0, 0, S, S, gl.RGBA, gl.FLOAT, px);
        for (let y = 0; y < S; y++)
          for (let x = 0; x < S; x++) {
            const s = ((x + 0.5) / S) * 2 - 1, t = ((y + 0.5) / S) * 2 - 1;
            let d = [[1, -t, -s], [-1, -t, s], [s, 1, t], [s, -1, -t], [s, -t, 1], [-s, -t, -1]][f];
            const l2 = 1 + s * s + t * t;
            const dw = (4 / (S * S)) / (l2 * Math.sqrt(l2));
            d = V.norm(d);
            const Y = [0.282095, 0.488603 * d[1], 0.488603 * d[2], 0.488603 * d[0], 1.092548 * d[0] * d[1],
              1.092548 * d[1] * d[2], 0.315392 * (3 * d[2] * d[2] - 1), 1.092548 * d[0] * d[2], 0.546274 * (d[0] * d[0] - d[1] * d[1])];
            const i = (y * S + x) * 4;
            for (let k = 0; k < 9; k++) for (let c = 0; c < 3; c++) sh[k][c] += px[i + c] * Y[k] * dw;
          }
      }
      const Ahat = [Math.PI, 2 * Math.PI / 3, 2 * Math.PI / 3, 2 * Math.PI / 3, Math.PI / 4, Math.PI / 4, Math.PI / 4, Math.PI / 4, Math.PI / 4];
      env.sh = new Float32Array(27);
      for (let k = 0; k < 9; k++) for (let c = 0; c < 3; c++) env.sh[k * 3 + c] = sh[k][c] * Ahat[k];
      // irradiance on an upward-facing floor (luminance) from env A
      const Yup = [0.282095, 0, 0.488603, 0, 0, 0, 0.315392 * 2, 0, 0];
      let eup = [0, 0, 0];
      for (let k = 0; k < 9; k++) for (let c = 0; c < 3; c++) eup[c] += env.sh[k * 3 + c] * Yup[k];
      env.envUp = 0.2126 * eup[0] + 0.7152 * eup[1] + 0.0722 * eup[2];
      env.boxes = boxes;
      gl.deleteFramebuffer(fb);
      this.envCache.set(key, env);
      return env;
    }

    // ---------------- per-size render targets
    ensureTargets(W, H, shadowSize, aoSize) {
      const t = this.targets;
      if (t && t.W === W && t.H === H && t.shadowSize === shadowSize && t.aoSize === aoSize) return t;
      const gl = this.gl;
      if (t) {
        for (const x of t.textures) gl.deleteTexture(x);
        for (const x of t.fbos) gl.deleteFramebuffer(x);
        for (const x of t.rbs) gl.deleteRenderbuffer(x);
      }
      const T = { W, H, shadowSize, aoSize, textures: [], fbos: [], rbs: [] };
      const tex = (w, h, i, f, ty, filt) => { const x = this.tex2D(w, h, i, f, ty, null, { filter: filt || gl.NEAREST }); T.textures.push(x); return x; };
      const fbo = (c, d) => { const f = this.fbo(c, d); T.fbos.push(f); return f; };
      const depth = this.depthRB(W, H); T.rbs.push(depth);
      T.aoObj = tex(W, H, gl.RGBA32F, gl.RGBA, gl.FLOAT);
      T.aoGround = tex(W, H, gl.RGBA32F, gl.RGBA, gl.FLOAT);
      T.aoFB = fbo([T.aoObj, T.aoGround], depth);
      T.aoObjF = tex(W, H, gl.RGBA32F, gl.RGBA, gl.FLOAT);
      T.aoGroundF = tex(W, H, gl.RGBA32F, gl.RGBA, gl.FLOAT);
      T.aoFillFB = fbo([T.aoObjF, T.aoGroundF], null);
      T.frame = tex(W, H, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT);
      T.frameFB = fbo([T.frame], depth);
      T.acc = tex(W, H, gl.RGBA32F, gl.RGBA, gl.FLOAT);
      T.accFB = fbo([T.acc], null);
      const w2 = Math.max(1, W >> 1), h2 = Math.max(1, H >> 1), w4 = Math.max(1, W >> 2), h4 = Math.max(1, H >> 2);
      T.bh = [tex(w2, h2, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, gl.LINEAR), tex(w2, h2, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, gl.LINEAR)];
      T.bq = [tex(w4, h4, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, gl.LINEAR), tex(w4, h4, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, gl.LINEAR)];
      T.bhFB = T.bh.map((x) => fbo([x], null));
      T.bqFB = T.bq.map((x) => fbo([x], null));
      T.out = tex(W, H, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE);
      T.outFB = fbo([T.out], null);
      T.shadow = this.depthArray(shadowSize, 3); T.textures.push(T.shadow.tex); T.fbos.push(T.shadow.fb);
      T.aoMaps = this.depthArray(aoSize, 8); T.textures.push(T.aoMaps.tex); T.fbos.push(T.aoMaps.fb);
      this.targets = T;
      return T;
    }

    ensureGround() {
      if (this.groundVAO) return;
      const gl = this.gl;
      this.groundVAO = gl.createVertexArray();
      gl.bindVertexArray(this.groundVAO);
      this.groundBuf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.groundBuf);
      gl.bufferData(gl.ARRAY_BUFFER, 4 * 3 * 4, gl.DYNAMIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.bindVertexArray(null);
    }

    // trilinear sampler with a given anisotropy (one per value); wrap modes follow the GLB's REPEAT default
    sampler(aniso) {
      const gl = this.gl;
      if (!this.samplers.has(aniso)) {
        const s = gl.createSampler();
        gl.samplerParameteri(s, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.samplerParameteri(s, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.samplerParameteri(s, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.samplerParameteri(s, gl.TEXTURE_WRAP_T, gl.REPEAT);
        if (this.anisoExt && aniso > 1) gl.samplerParameterf(s, this.anisoExt.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(aniso, this.maxAniso));
        this.samplers.set(aniso, s);
      }
      return this.samplers.get(aniso);
    }
    useMaterialSampler(aniso) {
      const gl = this.gl, s = aniso === null ? null : this.sampler(aniso);
      for (let u = 0; u < 5; u++) gl.bindSampler(u, s);
    }

    // ---------------- material binding
    bindMaterial(p, mat) {
      const gl = this.gl;
      const bind = (unit, tex) => { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, tex || this.white); };
      bind(0, mat.baseTex); bind(1, mat.normalTex); bind(2, mat.mrTex); bind(3, mat.emisTex); bind(4, mat.occlTex);
      p.i1('tBase', 0).i1('tNormal', 1).i1('tMR', 2).i1('tEmis', 3).i1('tOccl', 4);
      p.f4('uBaseFactor', mat.baseFactor).f2('uMR', mat.metallic, mat.roughness).f1('uNormalScale', mat.normalScale)
        .f3('uEmissive', mat.emissive).f1('uOcclStrength', mat.occlStrength).i1('uAlphaMode', mat.alphaMode)
        .f1('uAlphaCutoff', mat.alphaCutoff)
        .i4('uHas', [mat.baseTex ? 1 : 0, mat.normalTex ? 1 : 0, mat.mrTex ? 1 : 0, mat.emisTex ? 1 : 0])
        .i1('uHasOccl', mat.occlTex ? 1 : 0);
      const a = mat.aniso;
      if (a && a.strength > 0) {
        const mode = { 'uv-radial': 1, radial: 1, tangent: 2, 'model-radial': 3 }[a.mode] || 1;
        const c = a.center || (mode === 3 ? [0, 0] : [0.5, 0.5]);
        const mk = a.mask_roughness || [0, 0];
        p.f4('uAniso', [a.strength, a.roughness_across !== undefined ? a.roughness_across : 0.5, mode, a.roughness_along || 0]);
        p.f4('uAnisoP', [c[0], c[1], mk[0], mk[1]]);
      } else {
        p.f4('uAniso', [0, 0, 0, 0]).f4('uAnisoP', [0, 0, 0, 0]);
      }
    }

    effectiveMaterial(mat, overrides) {
      const o = overrides && overrides[mat.name];
      if (!o) return mat;
      const m = { ...mat };
      if (o.roughness !== undefined) m.roughness = o.roughness;
      if (o.metallic !== undefined) m.metallic = o.metallic;
      if (o.base_color) m.baseFactor = [...o.base_color.slice(0, 3), o.base_color[3] !== undefined ? o.base_color[3] : 1];
      if (o.emissive_scale !== undefined) m.emissive = m.emissive.map((c) => c * o.emissive_scale);
      if (o.normal_scale !== undefined) m.normalScale = o.normal_scale;
      if (o.anisotropy !== undefined) m.aniso = o.anisotropy;
      return m;
    }

    // ---------------- drawing helpers
    // draw every prim passing filter with the program pick(mat, prim) returns; setup(p) runs once per program
    drawPass(inst, filter, pick, setup) {
      const gl = this.gl, ready = new Set();
      let cur = null;
      for (const it of inst)
        for (const pr of it.model.prims) {
          const mat = it.mats.get(pr.material);
          if (!filter(mat)) continue;
          const p = pick(mat, pr);
          if (p !== cur) { p.use(); cur = p; if (!ready.has(p)) { setup(p); ready.add(p); } }
          p.m4('uModel', it.matrix).m3('uNormalMat', it.normal);
          this.bindMaterial(p, mat);
          gl.bindVertexArray(pr.vao);
          gl.drawElements(gl.TRIANGLES, pr.count, gl.UNSIGNED_INT, 0);
        }
    }

    drawScene(p, inst, filter, perPrim) {
      const gl = this.gl;
      for (const it of inst) {
        p.m4('uModel', it.matrix).m3('uNormalMat', it.normal);
        for (const pr of it.model.prims) {
          const mat = it.mats.get(pr.material);
          if (!filter(mat)) continue;
          if (perPrim) perPrim(mat);
          gl.bindVertexArray(pr.vao);
          gl.drawElements(gl.TRIANGLES, pr.count, gl.UNSIGNED_INT, 0);
        }
      }
      gl.disable(gl.CULL_FACE);
    }

    // ---------------- main entry
    async renderJob(job) {
      const gl = this.gl;
      const t0 = performance.now();
      const W = job.width | 0, H = job.height | 0;
      const frames = Math.max(1, job.samples | 0);                     // soft-box frames (soft shadows)
      const envFrames = Math.max(1, job.envSamples ? job.envSamples | 0 : Math.max(16, Math.ceil(frames / 3)));
      const aoFrames = Math.max(1, Math.ceil((job.aoSamples || 256) / 8));
      const NAO = 8;
      const shadowSize = job.shadowMapSize || 2048, aoSize = job.aoMapSize || 1024;
      const rig = job.rig || DEFAULT_RIG;
      const overrides = job.overrides || {};
      const shadowOpacity = job.shadow !== undefined ? job.shadow : 1;
      const texAniso = job.textureAniso !== undefined ? job.textureAniso : 4;

      // ---- scene
      const inst = [];
      for (const it of job.instances) {
        const model = await this.loadModel(it.url);
        const matrix = new Float32Array(it.matrix);
        const nm = M.normal3(matrix);
        const mats = new Map();
        for (const pr of model.prims) if (!mats.has(pr.material)) mats.set(pr.material, this.effectiveMaterial(pr.material, overrides));
        inst.push({ model, matrix, normal: nm.m, mats, name: it.name });
      }
      if (!inst.length) throw new Error('nothing to render');
      const pts = [];
      const bmin = [Infinity, Infinity, Infinity], bmax = [-Infinity, -Infinity, -Infinity];
      for (const it of inst)
        for (const pr of it.model.prims)
          for (let i = 0; i < pr.points.length; i += 3) {
            const p = M.point(it.matrix, [pr.points[i], pr.points[i + 1], pr.points[i + 2]]);
            pts.push(p);
            for (let k = 0; k < 3; k++) { bmin[k] = Math.min(bmin[k], p[k]); bmax[k] = Math.max(bmax[k], p[k]); }
          }
      const centre = V.mul(V.add(bmin, bmax), 0.5);
      let radius = 0;
      for (const p of pts) radius = Math.max(radius, V.len(V.sub(p, centre)));
      radius = Math.max(radius, 1e-3);
      const groundZ = job.ground === null || job.ground === false ? null
        : (typeof job.ground === 'number' ? job.ground : bmin[2] - radius * 1e-4);

      // ---- camera
      const cam = job.camera || {};
      const yaw = (cam.yaw !== undefined ? cam.yaw : 35) * D2R, pitch = (cam.pitch !== undefined ? cam.pitch : 18) * D2R;
      const fov = cam.fov || 30, aspect = W / H, margin = cam.margin !== undefined ? cam.margin : 0.06;
      const back = [-Math.sin(yaw) * Math.cos(pitch), Math.cos(yaw) * Math.cos(pitch), Math.sin(pitch)];
      const basis = (bk) => {
        const f = V.mul(bk, -1);
        const r = V.norm(V.cross(f, [0, 0, 1]));
        return { f, r, u: V.cross(r, f) };
      };
      const { f, r, u } = basis(back);
      const ky = Math.tan(fov * D2R / 2) * (1 - 2 * margin), kx = ky * aspect;
      let eye;
      if (cam.eye) eye = cam.eye;
      else if (cam.orbitYaws && cam.orbitYaws.length) {
        // fixed distance that fits every yaw (turntables / strips), orbiting the bounds centre
        const tgt = cam.target || centre;
        let d = 0;
        for (const yd of cam.orbitYaws) {
          const y2 = yd * D2R;
          const b2 = basis([-Math.sin(y2) * Math.cos(pitch), Math.cos(y2) * Math.cos(pitch), Math.sin(pitch)]);
          for (const p of pts) {
            const q = V.sub(p, tgt);
            const x = V.dot(q, b2.r), y = V.dot(q, b2.u), z = V.dot(q, b2.f);
            d = Math.max(d, Math.abs(x) / kx - z, Math.abs(y) / ky - z);
          }
        }
        d *= cam.distanceScale || 1;
        eye = V.sub(tgt, V.mul(f, d));
      } else if (cam.target && cam.distance) {
        eye = V.sub(cam.target, V.mul(f, cam.distance));
      } else {
        // tight fit of the silhouette inside the frustum (centred), any yaw/pitch
        let Ax = -Infinity, Bx = Infinity, Ay = -Infinity, By = Infinity;
        for (const p of pts) {
          const x = V.dot(p, r), y = V.dot(p, u), z = V.dot(p, f);
          Ax = Math.max(Ax, x - kx * z); Bx = Math.min(Bx, x + kx * z);
          Ay = Math.max(Ay, y - ky * z); By = Math.min(By, y + ky * z);
        }
        let cz = Math.min((Bx - Ax) / (2 * kx), (By - Ay) / (2 * ky));
        const cx = (Ax + Bx) / 2, cy = (Ay + By) / 2;
        if (cam.distanceScale) {
          // pull back along the view axis about the framed centre
          let zc = 0; for (const p of pts) zc += V.dot(p, f); zc /= pts.length;
          cz = zc - (zc - cz) * cam.distanceScale;
        }
        eye = V.add(V.add(V.mul(r, cx), V.mul(u, cy)), V.mul(f, cz));
      }
      let zmin = Infinity, zmax = -Infinity;
      for (const p of pts) { const z = V.dot(V.sub(p, eye), f); zmin = Math.min(zmin, z); zmax = Math.max(zmax, z); }
      const near = Math.max(zmin * 0.5, 1e-3), far = zmax + radius * 6;
      const view = M.view(eye, r, u, f);
      const proj = M.perspective(fov, aspect, near, far);
      const viewProj = M.mul(proj, view);

      // ---- environment frame (rig follows the camera's yaw)
      const env = this.ensureEnv(rig);
      const brdf = this.ensureBRDF();
      const ch = [back[0], back[1], 0];
      const chl = Math.hypot(ch[0], ch[1]) || 1;
      const ey = [ch[0] / chl, ch[1] / chl, 0];               // env +y (toward camera)
      const ex = [-ey[1], ey[0], 0];                           // env +x (camera right)
      const E2W = (d) => [ex[0] * d[0] + ey[0] * d[1], ex[1] * d[0] + ey[1] * d[1], d[2]];
      const W2E = new Float32Array([ex[0], ey[0], 0, ex[1], ey[1], 0, 0, 0, 1]); // column-major (transpose of [ex ey ez])

      // ---- area-light samples for the shadow casters
      const casters = env.boxes.filter((b) => b.shadow >= 0).sort((a, b) => a.shadow - b.shadow).slice(0, 3);
      const accents = env.boxes.filter((b) => b.accent && !(b.shadow >= 0)).slice(0, 2);
      const lightSamples = casters.map((b, i) => boxSamples(b, frames, 1 + i * 7919).map((s) => ({ dir: E2W(s.dir), E: s.E })));
      const accentSamples = accents.map((b, i) => boxSamples(b, frames, 5 + i * 104729).map((s) => ({ dir: E2W(s.dir), E: s.E })));
      // GGX alpha widening per light: about half the angular size of one sample's share of the box
      const widen = [...casters, ...accents].map((b, i) => {
        const smp = i < casters.length ? lightSamples[i] : accentSamples[i - casters.length];
        let m = 0;
        for (const x of smp) m += (x.E[0] + x.E[1] + x.E[2]) / (b.tint[0] + b.tint[1] + b.tint[2]);
        const solid = m / smp.length / b.L;                      // solid angle of the box (sr)
        return (job.lightWiden !== undefined ? job.lightWiden : 0.5) * Math.sqrt(solid / frames);
      });
      const lumE = (E) => 0.2126 * E[0] + 0.7152 * E[1] + 0.0722 * E[2];
      let unshadowed = env.envUp;
      for (const ls of lightSamples) {
        let m = 0;
        for (const s of ls) m += lumE(s.E) * Math.max(s.dir[2], 0);
        unshadowed += m / ls.length;
      }

      const T = this.ensureTargets(W, H, shadowSize, aoSize);
      this.ensureGround();
      // floor patch: only where a shadow can fall (footprint + ~1.6x the height + a little), faded at its rim
      let foot = 0;
      for (const p of pts) foot = Math.max(foot, Math.hypot(p[0] - centre[0], p[1] - centre[1]));
      const gsize = foot + 1.6 * (bmax[2] - bmin[2]) + 0.25 * radius;
      const gz = groundZ === null ? 0 : groundZ;
      gl.bindBuffer(gl.ARRAY_BUFFER, this.groundBuf);
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, new Float32Array([
        centre[0] - gsize, centre[1] - gsize, gz, centre[0] + gsize, centre[1] - gsize, gz,
        centre[0] - gsize, centre[1] + gsize, gz, centre[0] + gsize, centre[1] + gsize, gz]));

      // orthographic depth view around the scene sphere for a direction toward the "light"
      const sphereR = radius * 1.03;
      const dirVP = (d) => {
        const up = Math.abs(d[2]) < 0.99 ? [0, 0, 1] : [1, 0, 0];
        const ff = V.mul(d, -1);
        const rr = V.norm(V.cross(ff, up));
        const uu = V.cross(rr, ff);
        const ey2 = V.add(centre, V.mul(d, sphereR * 2));
        return M.mul(M.ortho(-sphereR, sphereR, -sphereR, sphereR, sphereR * 0.5, sphereR * 3.5), M.view(ey2, rr, uu, ff));
      };
      const casterFilter = (m) => m.alphaMode !== 2;
      const renderDepthLayer = (arr, layer, vp, size, offFactor, offUnits) => {
        gl.bindFramebuffer(gl.FRAMEBUFFER, arr.fb);
        gl.framebufferTextureLayer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, arr.tex, 0, layer);
        gl.drawBuffers([gl.NONE]);
        gl.readBuffer(gl.NONE);
        gl.viewport(0, 0, size, size);
        gl.clear(gl.DEPTH_BUFFER_BIT);
        gl.enable(gl.POLYGON_OFFSET_FILL);
        gl.polygonOffset(offFactor, offUnits);
        const p = this.p.depth.use().m4('uViewProj', vp);
        for (const it of inst) {
          p.m4('uModel', it.matrix);
          for (const pr of it.model.prims) {
            if (!casterFilter(it.mats.get(pr.material))) continue;
            gl.bindVertexArray(pr.vao);
            gl.drawElements(gl.TRIANGLES, pr.count, gl.UNSIGNED_INT, 0);
          }
        }
        gl.disable(gl.POLYGON_OFFSET_FILL);
      };
      const jitterVP = (i) => {
        const jx = tent(halton(i + 1, 2)), jy = tent(halton(i + 1, 3));
        const J = M.ident(); J[12] = (2 * jx) / W; J[13] = (2 * jy) / H;
        return M.mul(J, viewProj);
      };
      const prof = {};
      let profT = performance.now();
      // wait for the GPU: read one pixel of a tiny RGBA8 target (works whatever is bound)
      const hardSync = () => {
        const prev = gl.getParameter(gl.FRAMEBUFFER_BINDING);
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.syncFB);
        gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, this.syncPx);
        gl.bindFramebuffer(gl.FRAMEBUFFER, prev);
      };
      const mark = (name) => {
        if (!job.profile) return;
        hardSync();
        const now = performance.now();
        prof[name] = (prof[name] || 0) + (now - profT);
        profT = now;
      };
      const sync = async () => { hardSync(); await new Promise((r) => setTimeout(r, 0)); };

      gl.disable(gl.CULL_FACE);
      gl.disable(gl.BLEND);
      gl.enable(gl.DEPTH_TEST);
      gl.depthMask(true);

      // ================================================================ phase 1: visibility
      const t1 = performance.now();
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.aoFB);
      gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
      gl.viewport(0, 0, W, H);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      const nDirs = aoFrames * NAO;
      const golden = Math.PI * (3 - Math.sqrt(5));
      const fib = (i) => {
        const z = 1 - (2 * i + 1) / nDirs, rr = Math.sqrt(Math.max(0, 1 - z * z)), ph = i * golden;
        return [rr * Math.cos(ph), rr * Math.sin(ph), z];
      };
      const aoTexel = (2 * sphereR) / aoSize;
      for (let fi = 0; fi < aoFrames; fi++) {
        const dirs = [], vps = [];
        for (let k = 0; k < NAO; k++) {
          const d = fib(fi + k * aoFrames);
          dirs.push(...d);
          const vp = dirVP(d);
          vps.push(...vp);
          renderDepthLayer(T.aoMaps, k, vp, aoSize, 2.0, 4.0);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, T.aoFB);
        mark('p1_depthmaps');
        gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
        gl.viewport(0, 0, W, H);
        gl.clear(gl.DEPTH_BUFFER_BIT);
        const vpj = jitterVP(fi);
        // depth pre-pass so that only the front-most surface accumulates
        gl.colorMask(false, false, false, false);
        gl.depthFunc(gl.LESS); gl.depthMask(true);
        let p = this.p.prepass.use().m4('uViewProj', vpj);
        this.drawScene(p, inst, casterFilter);
        mark('p1_prepass');
        gl.colorMask(true, true, true, true);
        gl.depthFunc(gl.LEQUAL); gl.depthMask(false);
        gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE);
        const dirsF = new Float32Array(dirs), vpsF = new Float32Array(vps);
        gl.activeTexture(gl.TEXTURE5); gl.bindTexture(gl.TEXTURE_2D_ARRAY, T.aoMaps.tex);
        this.useMaterialSampler(1);
        this.drawPass(inst, casterFilter, (m, pr) => this.variant('ao', m, pr), (q) => {
          q.m4('uViewProj', vpj).f3('uCamPos', eye).i1('uNumDirs', NAO).f3v('uDirs', dirsF).m4v('uDirVP', vpsF)
            .f1('uMapTexel', aoTexel).f1('uMapSize', aoSize).i1('tMaps', 5);
        });
        this.useMaterialSampler(null);
        mark('p1_ao_obj');
        if (groundZ !== null) {
          const g = this.p.aoGround.use().m4('uViewProj', vpj).i1('uNumDirs', NAO)
            .f3v('uDirs', dirsF).m4v('uDirVP', vpsF)
            .f1('uMapTexel', aoTexel).f1('uMapSize', aoSize).i1('tMaps', 5);
          gl.depthFunc(gl.LESS);
          gl.bindVertexArray(this.groundVAO);
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
          void g;
          mark('p1_ao_ground');
        }
        gl.disable(gl.BLEND); gl.depthMask(true); gl.depthFunc(gl.LESS);
        if ((fi & 7) === 7) await sync();
      }
      // fill silhouette pixels that received no samples of their kind
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.aoFillFB);
      gl.viewport(0, 0, W, H);
      gl.disable(gl.DEPTH_TEST);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, T.aoObj);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, T.aoGround);
      this.p.aoFill.use().i1('tObj', 0).i1('tGround', 1);
      gl.bindVertexArray(this.emptyVAO);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.enable(gl.DEPTH_TEST);
      await sync();

      // ================================================================ phase 2: lighting
      // 2a "environment" frames: SH x AO diffuse, reflections of env A x occlusion, emissive, coverage (AA)
      // 2b "soft box" frames: the three shadow-casting boxes, one area sample each per frame (soft shadows),
      //    their diffuse light and reflections x shadow, plus the floor shadow
      const t2 = performance.now();
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.accFB);
      gl.viewport(0, 0, W, H);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      const shadowTexel = (2 * sphereR) / shadowSize;
      const nL = casters.length;
      const debugMode = { ao: 1, normal: 2, base: 3, spec: 4, diffuse: 5 }[job.debug] || 0;
      const fisBias = job.fisBias !== undefined ? job.fisBias : 0.5;
      const cubes = [[6, env.pre[0]], [8, env.raw[0]]];
      const anyBlend = inst.some((it) => [...it.mats.values()].some((m) => m.alphaMode === 2));
      const bindShared = () => {
        for (const [unit, tx] of cubes) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_CUBE_MAP, tx); }
        gl.activeTexture(gl.TEXTURE5); gl.bindTexture(gl.TEXTURE_2D_ARRAY, T.shadow.tex);
        gl.activeTexture(gl.TEXTURE10); gl.bindTexture(gl.TEXTURE_2D, brdf);
        gl.activeTexture(gl.TEXTURE11); gl.bindTexture(gl.TEXTURE_2D, T.aoObjF);
      };
      const xiFor = (fi, n) => { const a = new Float32Array(n * 2); for (let i = 0; i < n; i++) a.set(r2(fi * n + i + 11), i * 2); return a; };
      const accumulate = (weight) => {
        gl.bindFramebuffer(gl.FRAMEBUFFER, T.accFB);
        gl.viewport(0, 0, W, H);
        gl.disable(gl.DEPTH_TEST);
        gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE);
        this.p.copyAdd.use().i1('tSrc', 0).f1('uWeight', weight);
        gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, T.frame);
        gl.bindVertexArray(this.emptyVAO);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        gl.disable(gl.BLEND);
        gl.enable(gl.DEPTH_TEST);
      };
      const beginFrame = (vpj) => {
        gl.bindFramebuffer(gl.FRAMEBUFFER, T.frameFB);
        gl.drawBuffers([gl.COLOR_ATTACHMENT0]);
        gl.viewport(0, 0, W, H);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.colorMask(false, false, false, false);
        gl.depthFunc(gl.LESS); gl.depthMask(true);
        this.drawScene(this.p.prepass.use().m4('uViewProj', vpj), inst, casterFilter);
        gl.colorMask(true, true, true, true);
        gl.depthFunc(gl.LEQUAL); gl.depthMask(false);
      };
      const drawMaterials = (kind, setup, alphaKeep) => {
        this.useMaterialSampler(texAniso);
        this.drawPass(inst, (m) => m.alphaMode !== 2, (m, pr) => this.variant(kind, m, pr), setup);
        if (anyBlend) {             // translucent prints / decals over the opaque frame
          gl.enable(gl.BLEND);
          if (alphaKeep) gl.blendFuncSeparate(gl.ONE, gl.ONE_MINUS_SRC_ALPHA, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.ONE, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(-1, -2);
          this.drawPass(inst, (m) => m.alphaMode === 2, (m, pr) => this.variant(kind, m, pr), setup);
          gl.disable(gl.POLYGON_OFFSET_FILL);
          gl.disable(gl.BLEND);
        }
        this.useMaterialSampler(null);
      };
      const common = (q, vpj) => q.m4('uViewProj', vpj).f3('uCamPos', eye).m3('uW2E', W2E)
        .f1('uEnvLods', env.lods).f1('uEnvRawSize', env.rawSize).f2('uRes', W, H).f1('uFisBias', fisBias)
        .f1('uSpecOcc', job.specOcclusion !== undefined ? job.specOcclusion : 1.0).i1('uDebug', debugMode)
        .i1('tShadow', 5).i1('tBRDF', 10).i1('tAO', 11).i1('tEnvA', 6).i1('tEnvARaw', 8);

      // ---- 2a environment frames
      for (let fi = 0; fi < envFrames; fi++) {
        const vpj = jitterVP(fi);
        beginFrame(vpj);
        mark('p2a_prepass');
        bindShared();
        const xi = xiFor(fi, ANISO_SPP_ENV);
        drawMaterials('env', (q) => {
          common(q, vpj).f3v('uSH', env.sh).f1('uTotalSamples', envFrames * ANISO_SPP_ENV);
          const l = q.u('uXi'); if (l) gl.uniform2fv(l, xi);
        }, false);
        gl.depthMask(true); gl.depthFunc(gl.LESS);
        mark('p2a_shade');
        accumulate(1 / envFrames);
        mark('p2a_accumulate');
        if ((fi & 3) === 3) await sync();
      }
      // ---- 2b soft-box frames
      const t2b = performance.now();
      for (let fi = 0; fi < frames; fi++) {
        const ldirs = new Float32Array(15), lE = new Float32Array(15), lvp = new Float32Array(48), lez = new Float32Array(3);
        const lw = new Float32Array(5);
        for (let k = 0; k < accents.length; k++) {
          const smp = accentSamples[k][fi];
          ldirs.set(smp.dir, (3 + k) * 3);
          lE.set(smp.E, (3 + k) * 3);
          lw[3 + k] = widen[casters.length + k];
        }
        for (let k = 0; k < 3; k++) {
          if (k >= nL) { lvp.set(lvp.subarray(0, 16), k * 16); continue; }   // unused slot: zero irradiance
          const smp = lightSamples[k][fi];
          ldirs.set(smp.dir, k * 3);
          lE.set(smp.E, k * 3);
          lw[k] = widen[k];
          lez[k] = lumE(smp.E) * Math.max(smp.dir[2], 0);
          const vp = dirVP(smp.dir);
          lvp.set(vp, k * 16);
          renderDepthLayer(T.shadow, k, vp, shadowSize, 1.5, 3.0);
        }
        mark('p2b_shadowmaps');
        const vpj = jitterVP(fi);
        beginFrame(vpj);
        mark('p2b_prepass');
        bindShared();
        const xi = xiFor(fi + 7919, ANISO_SPP_LIGHTS);
        const lightUniforms = (q) => q.i1('uNumLights', nL).f3v('uLDir', ldirs).f3v('uLE', lE).f1v('uLWiden', lw)
          .m4v('uLVP', lvp).f1('uShadowTexel', shadowTexel).f1('uShadowSize', shadowSize);
        drawMaterials('lights', (q) => {
          lightUniforms(common(q, vpj)).f1('uTotalSamples', frames * ANISO_SPP_LIGHTS);
          const l = q.u('uXi'); if (l) gl.uniform2fv(l, xi);
        }, true);
        mark('p2b_shade');
        if (groundZ !== null && shadowOpacity > 0) {
          const g = lightUniforms(this.p.ground.use());
          g.m4('uViewProj', vpj).f2('uRes', W, H).f1('uEnvUp', env.envUp).f1v('uLEz', lez).f1('uUnshadowed', unshadowed)
            .f1('uOpacity', shadowOpacity).f3('uFadeCentre', centre).f1('uFadeRadius', gsize * 0.95)
            .f1('uEdgeFade', job.edgeFade !== undefined ? job.edgeFade : 0.06).i1('tShadow', 5).i1('tAOG', 11);
          gl.activeTexture(gl.TEXTURE11); gl.bindTexture(gl.TEXTURE_2D, T.aoGroundF);
          gl.depthFunc(gl.LESS);
          gl.bindVertexArray(this.groundVAO);
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
          mark('p2b_ground');
        }
        gl.depthMask(true); gl.depthFunc(gl.LESS);
        accumulate(1 / frames);
        mark('p2b_accumulate');
        if ((fi & 3) === 3) await sync();
      }
      await sync();

      // ================================================================ post
      const t3 = performance.now();
      gl.disable(gl.DEPTH_TEST);
      gl.bindVertexArray(this.emptyVAO);
      const exposure = job.exposure !== undefined ? job.exposure : 1;
      const w2 = T.bh[0].w, h2 = T.bh[0].h, w4 = T.bq[0].w, h4 = T.bq[0].h;
      const bloom = job.bloom !== undefined ? job.bloom : 1;
      if (bloom > 0) {
        gl.bindFramebuffer(gl.FRAMEBUFFER, T.bhFB[0]); gl.viewport(0, 0, w2, h2);
        gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, T.acc);
        this.p.bright.use().i1('tAcc', 0).f1('uScale', exposure).f1('uThreshold', job.bloomThreshold || 1.6).f2('uSrcRes', W, H);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        const blur = (src, dstFB, w, h, dx, dy, sigma) => {
          gl.bindFramebuffer(gl.FRAMEBUFFER, dstFB); gl.viewport(0, 0, w, h);
          gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, src);
          this.p.blur.use().i1('tSrc', 0).f2('uDir', dx / w, dy / h).f1('uSigma', sigma);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
        };
        // quarter-res wide blur from the half-res bright pass
        gl.bindFramebuffer(gl.FRAMEBUFFER, T.bqFB[0]); gl.viewport(0, 0, w4, h4);
        gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, T.bh[0]);
        this.p.down.use().i1('tSrc', 0).f2('uSrcRes', w2, h2);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        const sA = Math.max(1, W * 0.004), sB = Math.max(1, W * 0.012);
        blur(T.bh[0], T.bhFB[1], w2, h2, 1, 0, sA); blur(T.bh[1], T.bhFB[0], w2, h2, 0, 1, sA);
        blur(T.bq[0], T.bqFB[1], w4, h4, 1, 0, sB); blur(T.bq[1], T.bqFB[0], w4, h4, 0, 1, sB);
      } else {
        for (const fb of [T.bhFB[0], T.bqFB[0]]) { gl.bindFramebuffer(gl.FRAMEBUFFER, fb); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); }
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, T.outFB);
      gl.viewport(0, 0, W, H);
      const fp = this.p.final.use();
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, T.acc);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, T.bh[0]);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, T.bq[0]);
      const bg = job.background ? [...job.background, 1] : [0, 0, 0, 0];
      fp.i1('tAcc', 0).i1('tBloomA', 1).i1('tBloomB', 2).f1('uInvFrames', 1).f1('uExposure', exposure)
        .f1('uBloom', bloom).i1('uTonemap', { agx: 0, aces: 1, neutral: 2, linear: 3 }[job.tonemap || 'agx'] || 0)
        .f4('uBg', bg).f2('uRes', W, H).f1('uDither', job.dither !== undefined ? job.dither : 1.0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      const out = new Uint8Array(W * H * 4);
      gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, out);
      const err = gl.getError();
      if (err) throw new Error(`WebGL error 0x${err.toString(16)}`);
      const t4 = performance.now();
      // base64 (rows are bottom-up; the caller flips)
      let s = '';
      for (let i = 0; i < out.length; i += 0x8000) s += String.fromCharCode.apply(null, out.subarray(i, i + 0x8000));
      return {
        b64: btoa(s), width: W, height: H,
        stats: {
          gpu: this.gpu, tris: inst.reduce((a, it) => a + it.model.tris, 0), frames, envFrames, aoDirections: nDirs,
          ms: { setup: Math.round(t1 - t0), visibility: Math.round(t2 - t1), environment: Math.round(t2b - t2),
            lights: Math.round(t3 - t2b), post: Math.round(t4 - t3) },
          profile: job.profile ? Object.fromEntries(Object.entries(prof).map(([k, v]) => [k, Math.round(v)])) : undefined,
          camera: { eye, fov, near, far }, bounds: { min: bmin, max: bmax, radius }, ground: groundZ,
        },
      };
    }
  }

  let R = null;
  window.NZ = {
    ready: true,
    async renderJob(job) {
      if (!R) R = new Renderer();
      return R.renderJob(job);
    },
    info() { if (!R) R = new Renderer(); return { gpu: R.gpu, maxAniso: R.maxAniso }; },
    DEFAULT_RIG,
  };
})();
