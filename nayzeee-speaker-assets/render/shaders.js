// nayzeee product-shot renderer: GLSL ES 3.00 shaders (hand written, no 3D library).
// World space is the GTA model space: metres, +Z up, +Y = model front.
'use strict';

(function (root) {
  const HEAD = `#version 300 es
//DEFINES
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp samplerCube;
precision highp sampler2DArrayShadow;
#define PI 3.14159265358979
`;

  // ---------------------------------------------------------------- common helpers
  const COMMON = `
float sat(float x) { return clamp(x, 0.0, 1.0); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// cube face texel -> direction, following the GL cube map table (s right, t up in FBO space)
vec3 faceDir(int f, vec2 st) {
  vec2 c = st * 2.0 - 1.0;
  if (f == 0) return vec3(1.0, -c.y, -c.x);
  if (f == 1) return vec3(-1.0, -c.y, c.x);
  if (f == 2) return vec3(c.x, 1.0, c.y);
  if (f == 3) return vec3(c.x, -1.0, -c.y);
  if (f == 4) return vec3(c.x, -c.y, 1.0);
  return vec3(-c.x, -c.y, -1.0);
}

float radicalInverse(uint b) {
  b = (b << 16u) | (b >> 16u);
  b = ((b & 0x55555555u) << 1u) | ((b & 0xAAAAAAAAu) >> 1u);
  b = ((b & 0x33333333u) << 2u) | ((b & 0xCCCCCCCCu) >> 2u);
  b = ((b & 0x0F0F0F0Fu) << 4u) | ((b & 0xF0F0F0F0u) >> 4u);
  b = ((b & 0x00FF00FFu) << 8u) | ((b & 0xFF00FF00u) >> 8u);
  return float(b) * 2.3283064365386963e-10;
}
vec2 hammersley(int i, int n) { return vec2((float(i) + 0.5) / float(n), radicalInverse(uint(i))); }

float D_GGX(float NdotH, float a) {
  float a2 = a * a;
  float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
  return a2 / (PI * d * d);
}
float V_SmithGGXCorrelated(float NdotV, float NdotL, float a) {
  float a2 = a * a;
  float gv = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
  float gl = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
  return 0.5 / max(gv + gl, 1e-7);
}
vec3 importanceSampleGGX(vec2 xi, float a) {
  float phi = 2.0 * PI * xi.x;
  float cosT = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
  float sinT = sqrt(max(0.0, 1.0 - cosT * cosT));
  return vec3(sinT * cos(phi), sinT * sin(phi), cosT);
}
// cheap per-pixel hash (interleaved gradient noise) for Cranley-Patterson rotation / dither
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
`;

  // ---------------------------------------------------------------- fullscreen triangle
  const FULLSCREEN_VS = HEAD + `
out vec2 vUV;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  vUV = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

  // ---------------------------------------------------------------- procedural studio environment
  // Soft gradient studio + the soft boxes that are not lit analytically (.w < -0.5 in uBoxL).
  const ENV_FS = HEAD + COMMON + `
uniform int uFace;
uniform float uSize;
uniform int uBoxCount;
uniform vec3 uBoxC[8];
uniform vec3 uBoxU[8];
uniform vec3 uBoxV[8];
uniform vec4 uBoxS[8];   // tan half width, tan half height, corner radius, edge softness (gnomonic units)
uniform vec4 uBoxL[8];   // rgb radiance; .w = -1 baked into the map, otherwise skipped (analytic light)
uniform vec3 uSkyTop;
uniform vec3 uSkyHorizon;
uniform vec3 uFloorHorizon;
uniform vec3 uFloorBottom;
out vec4 o;

float boxProfile(vec3 d, int i) {
  float dc = dot(d, uBoxC[i]);
  if (dc <= 0.05) return 0.0;
  vec2 p = vec2(dot(d, uBoxU[i]), dot(d, uBoxV[i])) / dc;
  vec4 s = uBoxS[i];
  vec2 q = abs(p) - s.xy + s.z;
  float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - s.z;
  float edge = 1.0 - smoothstep(-s.w, s.w, sd);
  vec2 n = p / s.xy;
  float fall = 1.0 - 0.28 * min(dot(n, n), 1.5);
  return edge * fall;
}

vec3 baseEnv(vec3 d) {
  float z = d.z;
  vec3 sky = mix(uSkyHorizon, uSkyTop, smoothstep(0.0, 0.9, z));
  vec3 flo = mix(uFloorHorizon, uFloorBottom, smoothstep(0.0, 0.5, -z));
  return mix(flo, sky, smoothstep(-0.06, 0.06, z));
}

void main() {
  vec3 d = normalize(faceDir(uFace, gl_FragCoord.xy / uSize));
  vec3 col = baseEnv(d);
  for (int i = 0; i < 8; i++) {
    if (i >= uBoxCount) break;
    if (uBoxL[i].w > -0.5) continue;
    col += boxProfile(d, i) * uBoxL[i].rgb;
  }
  o = vec4(col, 1.0);
}`;

  // GGX pre-filter of a cube map for one roughness (split-sum, N = V = R), filtered importance sampling.
  const PREFILTER_FS = HEAD + COMMON + `
uniform samplerCube uSrc;
uniform int uFace;
uniform float uSize;
uniform float uSrcSize;
uniform float uRough;
uniform int uSamples;
out vec4 o;
void main() {
  vec3 N = normalize(faceDir(uFace, gl_FragCoord.xy / uSize));
  float a = max(uRough * uRough, 1e-4);
  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 T = normalize(cross(up, N));
  vec3 B = cross(N, T);
  vec3 sum = vec3(0.0);
  float wsum = 0.0;
  float saTexel = 4.0 * PI / (6.0 * uSrcSize * uSrcSize);
  for (int i = 0; i < 2048; i++) {
    if (i >= uSamples) break;
    vec3 h = importanceSampleGGX(hammersley(i, uSamples), a);
    vec3 H = T * h.x + B * h.y + N * h.z;
    vec3 L = 2.0 * dot(N, H) * H - N;
    float NdotL = dot(N, L);
    if (NdotL > 0.0) {
      float pdf = D_GGX(h.z, a) * 0.25;
      float saSample = 1.0 / (float(uSamples) * pdf + 1e-6);
      float lod = max(0.5 * log2(saSample / saTexel) + 1.0, 0.0);
      sum += textureLod(uSrc, L, lod).rgb * NdotL;
      wsum += NdotL;
    }
  }
  o = vec4(sum / max(wsum, 1e-6), 1.0);
}`;

  // Split-sum DFG lookup table: x = NdotV, y = perceptual roughness -> (scale, bias).
  const BRDF_LUT_FS = HEAD + COMMON + `
uniform float uSize;
out vec4 o;
void main() {
  float NdotV = (gl_FragCoord.x) / uSize;
  float rough = (gl_FragCoord.y) / uSize;
  float a = max(rough * rough, 1e-4);
  vec3 V = vec3(sqrt(1.0 - NdotV * NdotV), 0.0, NdotV);
  float A = 0.0, B = 0.0;
  const int NS = 512;
  for (int i = 0; i < NS; i++) {
    vec3 H = importanceSampleGGX(hammersley(i, NS), a);
    vec3 L = 2.0 * dot(V, H) * H - V;
    float NdotL = sat(L.z);
    float NdotH = sat(H.z);
    float VdotH = sat(dot(V, H));
    if (NdotL > 0.0) {
      float Vis = V_SmithGGXCorrelated(NdotV, NdotL, a);
      float G = 4.0 * Vis * NdotL * VdotH / max(NdotH, 1e-6);
      float Fc = pow(1.0 - VdotH, 5.0);
      A += (1.0 - Fc) * G;
      B += Fc * G;
    }
  }
  o = vec4(A / float(NS), B / float(NS), 0.0, 1.0);
}`;

  // ---------------------------------------------------------------- mesh vertex shaders
  const MESH_VS = HEAD + `
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec4 aTangent;
layout(location = 3) in vec2 aUV;
layout(location = 4) in vec4 aColor;
uniform mat4 uModel;
uniform mat3 uNormalMat;
uniform mat4 uViewProj;
out vec3 vWorld;
out vec3 vNormal;
out vec4 vTangent;
out vec2 vUV;
out vec4 vColor;
out vec3 vLocal;
void main() {
  vec4 w = uModel * vec4(aPos, 1.0);
  vWorld = w.xyz;
  vNormal = uNormalMat * aNormal;
  vTangent = vec4(mat3(uModel) * aTangent.xyz, aTangent.w);
  vUV = aUV;
  vColor = aColor;
  vLocal = aPos;
  gl_Position = uViewProj * w;
}`;

  const DEPTH_VS = HEAD + `
layout(location = 0) in vec3 aPos;
uniform mat4 uModel;
uniform mat4 uViewProj;
void main() { gl_Position = uViewProj * (uModel * vec4(aPos, 1.0)); }`;

  const DEPTH_FS = HEAD + `
void main() {}`;

  // ---------------------------------------------------------------- shared material code
  const MATERIAL = `
in vec3 vWorld;
in vec3 vNormal;
in vec4 vTangent;
in vec2 vUV;
in vec4 vColor;
in vec3 vLocal;

uniform vec4 uBaseFactor;
uniform vec2 uMR;              // metallic, roughness factors
uniform float uNormalScale;
uniform vec3 uEmissive;        // factor * strength
uniform float uOcclStrength;
uniform int uAlphaMode;        // 0 opaque, 1 mask, 2 blend
uniform float uAlphaCutoff;
uniform ivec4 uHas;            // base, normal, mr, emissive
uniform int uHasOccl;
uniform sampler2D tBase;
uniform sampler2D tNormal;
uniform sampler2D tMR;
uniform sampler2D tEmis;
uniform sampler2D tOccl;
uniform vec3 uCamPos;

struct Surf {
  vec3 P;
  vec3 Ng;      // interpolated vertex normal (facing the viewer for two-sided)
  vec3 N;       // shading normal (normal mapped)
  vec3 T;       // tangent (orthogonalised against N)
  vec3 B;
  vec3 base;
  float alpha;
  float metal;
  float rough;
  float nlen;   // length of the filtered normal-map normal (Toksvig)
  float occl;
};

Surf surface() {
  Surf s;
  s.P = vWorld;
  vec3 Ng = normalize(vNormal);
  vec3 T = vTangent.xyz;
  float tw = vTangent.w;
  if (!gl_FrontFacing) Ng = -Ng;
#ifdef NO_TANGENT
  {
    vec3 dp1 = dFdx(vWorld), dp2 = dFdy(vWorld);
    vec2 du1 = dFdx(vUV), du2 = dFdy(vUV);
    vec3 dp2perp = cross(dp2, Ng), dp1perp = cross(Ng, dp1);
    T = dp2perp * du1.x + dp1perp * du2.x;
    vec3 Bv = dp2perp * du1.y + dp1perp * du2.y;
    float inv = inversesqrt(max(max(dot(T, T), dot(Bv, Bv)), 1e-20));
    T *= inv;
    tw = dot(cross(Ng, T), Bv * inv) < 0.0 ? -1.0 : 1.0;
  }
#endif
  T = normalize(T - Ng * dot(Ng, T) + 1e-9);
  // handedness: B points image-up on both faces of two-sided surfaces
  float hs = (tw < 0.0 ? -1.0 : 1.0) * (gl_FrontFacing ? 1.0 : -1.0);
  vec3 B = cross(Ng, T) * hs;
  vec3 N = Ng;
  s.nlen = 1.0;
  if (uHas.y == 1) {
    vec3 tn = texture(tNormal, vUV).xyz * 2.0 - 1.0;
    s.nlen = clamp(length(tn), 0.05, 1.0);
    tn.xy *= uNormalScale;
    N = normalize(T * tn.x + B * tn.y + Ng * max(tn.z, 1e-3));
  }
  s.Ng = Ng;
  s.N = N;
  s.T = normalize(T - N * dot(N, T) + 1e-9);
  s.B = cross(N, s.T) * hs;
  vec4 bc = uBaseFactor * vColor;
  if (uHas.x == 1) bc *= texture(tBase, vUV);
  s.base = bc.rgb;
  s.alpha = bc.a;
  float metal = uMR.x, rough = uMR.y;
  if (uHas.z == 1) {
    vec4 mr = texture(tMR, vUV);
    rough *= mr.g;
    metal *= mr.b;
  }
  s.metal = sat(metal);
  s.rough = clamp(rough, 0.03, 1.0);
  s.occl = 1.0;
  if (uHasOccl == 1) s.occl = mix(1.0, texture(tOccl, vUV).r, uOcclStrength);
  return s;
}
`;

  // ---------------------------------------------------------------- phase 1: visibility (AO + specular occlusion)
  // Accumulates, per pixel, visibility from many directions (one orthographic depth map each):
  //   object target: (sum V*cos, sum cos, sum V*lobe, sum lobe)   lobe = cone around the reflection vector
  //   ground target: (sum V*cos_up, sum cos_up, 0, 0)
  const AO_FS = HEAD + COMMON + MATERIAL + `
uniform int uNumDirs;
uniform vec3 uDirs[8];
uniform mat4 uDirVP[8];
uniform highp sampler2DArrayShadow tMaps;
uniform float uMapTexel;     // world size of one depth-map texel
uniform float uMapSize;
layout(location = 0) out vec4 oObj;
layout(location = 1) out vec4 oGround;

float visDir(int j, vec3 P) {
  vec4 c = uDirVP[j] * vec4(P, 1.0);
  vec3 s = c.xyz * 0.5 + 0.5;
  if (s.x <= 0.0 || s.y <= 0.0 || s.x >= 1.0 || s.y >= 1.0 || s.z >= 1.0) return 1.0;
  return texture(tMaps, vec4(s.xy, float(j), s.z));
}

void main() {
  Surf s = surface();
#ifdef ALPHA_MASK
  if (s.alpha < uAlphaCutoff) discard;
#endif
  vec3 V = normalize(uCamPos - s.P);
  vec3 R = reflect(-V, s.N);
  float a = s.rough * s.rough;
  float n = clamp(2.0 / max(a * a, 1e-4) - 2.0, 2.0, 16.0);
  vec4 acc = vec4(0.0);
  for (int j = 0; j < 8; j++) {
    if (j >= uNumDirs) break;
    vec3 w = uDirs[j];
    float c = max(dot(s.N, w), 0.0);
    float lw = pow(max(dot(R, w), 0.0), n) * step(0.0, dot(s.Ng, w));
    if (c <= 0.0 && lw <= 0.0) continue;
    float ndl = max(dot(s.Ng, w), 0.0);
    vec3 Po = s.P + s.Ng * uMapTexel * (1.5 + 2.5 * (1.0 - ndl)) + w * uMapTexel * 1.0;
    float v = visDir(j, Po);
    acc += vec4(v * c, c, v * lw, lw);
  }
  oObj = acc;
  oGround = vec4(0.0);
}`;

  const AO_GROUND_FS = HEAD + COMMON + `
in vec3 vWorld;
uniform int uNumDirs;
uniform vec3 uDirs[8];
uniform mat4 uDirVP[8];
uniform highp sampler2DArrayShadow tMaps;
uniform float uMapTexel;
uniform float uMapSize;
layout(location = 0) out vec4 oObj;
layout(location = 1) out vec4 oGround;
float visDir(int j, vec3 P) {
  vec4 c = uDirVP[j] * vec4(P, 1.0);
  vec3 s = c.xyz * 0.5 + 0.5;
  if (s.x <= 0.0 || s.y <= 0.0 || s.x >= 1.0 || s.y >= 1.0 || s.z >= 1.0) return 1.0;
  return texture(tMaps, vec4(s.xy, float(j), s.z));
}
void main() {
  vec4 acc = vec4(0.0);
  for (int j = 0; j < 8; j++) {
    if (j >= uNumDirs) break;
    vec3 w = uDirs[j];
    float c = max(w.z, 0.0);
    if (c <= 0.0) continue;
    acc.x += visDir(j, vWorld + vec3(0.0, 0.0, uMapTexel * 0.5)) * c;
    acc.y += c;
  }
  oObj = vec4(0.0);
  oGround = acc;
}`;

  const GROUND_VS = HEAD + `
layout(location = 0) in vec3 aPos;
uniform mat4 uViewProj;
out vec3 vWorld;
void main() { vWorld = aPos; gl_Position = uViewProj * vec4(aPos, 1.0); }`;

  // ---------------------------------------------------------------- phase 2: shading
  // Lights evaluated per frame: slots 0..2 = shadow-casting soft boxes (one area sample per frame,
  // shadow map per slot), slots 3..4 = small unshadowed accent lights (occluded by AO / reflection occlusion).
  const LIGHTS = `
uniform int uNumLights;
uniform vec3 uLDir[5];       // world direction toward this frame's sample of each light
uniform vec3 uLE[5];         // irradiance at normal incidence of that sample (rgb, tint included)
uniform float uLWiden[5];    // GGX alpha added so successive samples blend into the box's reflection
uniform mat4 uLVP[3];
uniform highp sampler2DArrayShadow tShadow;
uniform float uShadowTexel;  // world size of one shadow texel
uniform float uShadowSize;

float shadowK(int k, vec3 P, vec3 Ng) {
  vec3 L = uLDir[k];
  float ndl = sat(dot(Ng, L));
  vec3 Po = P + Ng * uShadowTexel * (1.2 + 2.0 * (1.0 - ndl)) + L * uShadowTexel * 0.75;
  vec4 c = uLVP[k] * vec4(Po, 1.0);
  vec3 s = c.xyz * 0.5 + 0.5;
  if (s.x <= 0.0 || s.y <= 0.0 || s.x >= 1.0 || s.y >= 1.0 || s.z >= 1.0) return 1.0;
  return texture(tShadow, vec4(s.xy, float(k), s.z));   // hardware 2x2 PCF; frames jitter the light
}
`;

  const MAIN_FS = HEAD + COMMON + MATERIAL + LIGHTS + `
#ifndef ANISO_SAMPLES
#define ANISO_SAMPLES 2
#endif
uniform vec4 uAniso;         // strength, roughness across the grooves, mode (1 uv-radial, 2 tangent, 3 model-radial), roughness along (0 = material)
uniform vec4 uAnisoP;        // centre (uv or model xy), roughness-mask lo, hi (off when lo >= hi)
uniform mat4 uModel;
uniform mat3 uW2E;           // world -> environment frame
uniform vec3 uSH[9];         // irradiance SH (already convolved) of the environment
uniform samplerCube tEnvA;   // GGX pre-filtered, roughness = lod / uEnvLods
uniform samplerCube tEnvARaw;  // box-filtered mips (filtered importance sampling)
uniform float uEnvLods;
uniform float uEnvRawSize;
uniform sampler2D tBRDF;
uniform sampler2D tAO;
uniform vec2 uRes;
uniform vec2 uXi[ANISO_SAMPLES];   // this frame's stratified 2D samples (anisotropic reflections)
uniform float uTotalSamples; // frames * samples per frame (for the FIS lod)
uniform float uFisBias;      // extra blur (mip levels) for the filtered importance sampling
uniform float uSpecOcc;      // 0..1 strength of the reflection occlusion
uniform int uDebug;          // 0 beauty, 1 ao, 2 normal, 3 base colour, 4 specular, 5 diffuse
layout(location = 0) out vec4 o;

vec3 shIrr(vec3 n) {
  vec3 r = uSH[0] * 0.282095;
  r += uSH[1] * 0.488603 * n.y + uSH[2] * 0.488603 * n.z + uSH[3] * 0.488603 * n.x;
  r += uSH[4] * 1.092548 * n.x * n.y + uSH[5] * 1.092548 * n.y * n.z;
  r += uSH[6] * 0.315392 * (3.0 * n.z * n.z - 1.0);
  r += uSH[7] * 1.092548 * n.x * n.z + uSH[8] * 0.546274 * (n.x * n.x - n.y * n.y);
  return max(r, vec3(0.0));
}
float lambdaAniso(vec3 w, float ax, float ay) {
  float z2 = max(w.z * w.z, 1e-7);
  return 0.5 * (-1.0 + sqrt(1.0 + (ax * ax * w.x * w.x + ay * ay * w.y * w.y) / z2));
}
float D_aniso(vec3 h, float ax, float ay) {
  float x = h.x / ax, y = h.y / ay;
  float d = x * x + y * y + h.z * h.z;
  return 1.0 / (PI * ax * ay * d * d);
}
// Heitz 2018: sample the visible normals of anisotropic GGX (local frame, z = N)
vec3 sampleVNDF(vec3 Ve, float ax, float ay, vec2 u) {
  vec3 Vh = normalize(vec3(ax * Ve.x, ay * Ve.y, Ve.z));
  float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
  vec3 T1 = lensq > 0.0 ? vec3(-Vh.y, Vh.x, 0.0) * inversesqrt(lensq) : vec3(1.0, 0.0, 0.0);
  vec3 T2 = cross(Vh, T1);
  float r = sqrt(u.x);
  float phi = 2.0 * PI * u.y;
  float t1 = r * cos(phi);
  float t2 = r * sin(phi);
  float s = 0.5 * (1.0 + Vh.z);
  t2 = (1.0 - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;
  vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;
  return normalize(vec3(ax * Nh.x, ay * Nh.y, max(1e-6, Nh.z)));
}

// One light, constant index (unrolled: SwiftShader is slow with dynamically indexed loops).
// Accumulates irradiance x visibility into E and the reflection into spec.
#define LIGHT_ISO(K, VD, VS) { \
  vec3 L_ = uLDir[K]; float nl_ = dot(N, L_); \
  if (nl_ > 0.0) { \
    E += uLE[K] * (nl_ * (VD)); \
    vec3 H_ = normalize(V + L_); float x_ = 1.0 - sat(dot(V, H_)); float x2_ = x_ * x_; \
    vec3 F_ = F0 + (1.0 - F0) * (x2_ * x2_ * x_); \
    float aw_ = sqrt(aT * aT + uLWiden[K] * uLWiden[K]); \
    float hz_ = sat(1.0 + 1.3 * dot(L_, s.Ng)); \
    spec += F_ * ms * (D_GGX(sat(dot(N, H_)), aw_) * V_SmithGGXCorrelated(NdotV, nl_, aw_) * nl_ * (VS) * hz_) * uLE[K]; \
  } }
#define LIGHT_ANISO(K, VD, VS) { \
  vec3 L_ = uLDir[K]; float nl_ = dot(N, L_); \
  if (nl_ > 0.0) { \
    E += uLE[K] * (nl_ * (VD)); \
    vec3 H_ = normalize(V + L_); float x_ = 1.0 - sat(dot(V, H_)); float x2_ = x_ * x_; \
    vec3 F_ = F0 + (1.0 - F0) * (x2_ * x2_ * x_); \
    float w_ = uLWiden[K]; float ax_ = sqrt(as_ * as_ + w_ * w_), ay_ = sqrt(ag * ag + w_ * w_); \
    vec3 h_ = vec3(dot(H_, sdir), dot(H_, gdir), dot(H_, N)); \
    vec3 l_ = vec3(dot(L_, sdir), dot(L_, gdir), nl_); \
    float G2_ = 1.0 / (1.0 + lambdaAniso(Ve, ax_, ay_) + lambdaAniso(l_, ax_, ay_)); \
    float hz_ = sat(1.0 + 1.3 * dot(L_, s.Ng)); \
    spec += F_ * (D_aniso(h_, ax_, ay_) * G2_ / (4.0 * NdotV) * (VS) * hz_) * uLE[K]; \
  } }

void main() {
  Surf s = surface();
#ifdef ALPHA_MASK
  if (s.alpha < uAlphaCutoff) discard;
#endif
  vec3 V = normalize(uCamPos - s.P);
  vec3 N = s.N;
  float nv = dot(N, V);                      // keep normal-mapped normals facing the viewer
  if (nv < 0.02) N = normalize(N + V * (0.02 - nv));
  float NdotV = max(dot(N, V), 1e-4);
  vec3 diffColor = s.base * (1.0 - s.metal);
  vec3 F0 = mix(vec3(0.04), s.base, s.metal);
  float a = s.rough * s.rough;

  // ---------------- visibility from phase 1 (ambient occlusion, reflection occlusion)
  vec4 aoAcc = texelFetch(tAO, ivec2(gl_FragCoord.xy), 0);
  float ao = aoAcc.y > 1e-4 ? aoAcc.x / aoAcc.y : 1.0;
  float soLobe = aoAcc.w > 1e-4 ? aoAcc.z / aoAcc.w : ao;
  ao *= s.occl;
  float soLag = sat(pow(NdotV + ao, exp2(-16.0 * a - 1.0)) - 1.0 + ao);
  float so = mix(1.0, min(min(soLobe, soLag + 0.15), soLag + 0.25), uSpecOcc);

  // ---------------- microfacet frame
#ifdef ANISO
  vec3 gdir;
  float mode = uAniso.z;
  if (mode < 1.5) {                 // uv-radial: grooves are circles around the uv centre
    vec2 d = vUV - uAnisoP.xy;
    gdir = cross(N, normalize(s.T * d.x - s.B * d.y + 1e-9));   // +v is image-down, B points image-up
  } else if (mode < 2.5) {          // tangent: grooves run along U
    gdir = s.T;
  } else {                          // model-radial about the model +Z axis
    gdir = cross(N, normalize(mat3(uModel) * vec3(vLocal.xy - uAnisoP.xy, 0.0) + 1e-9));
  }
  gdir = normalize(gdir - N * dot(N, gdir) + 1e-9);
  vec3 sdir = cross(N, gdir);       // across the grooves (rough direction)
  float mask = 1.0;
  if (uAnisoP.w > uAnisoP.z) {
    float rr = uHas.z == 1 ? texture(tMR, vUV).g * uMR.y : uMR.y;
    mask = smoothstep(uAnisoP.z, uAnisoP.w, rr);
  }
  float aniso = uAniso.x * mask;
  float ag = max(uAniso.w > 0.0 ? mix(a, uAniso.w * uAniso.w, aniso) : a, 0.002);
  float as_ = max(mix(a, uAniso.y * uAniso.y, aniso), ag);
  vec3 Ve = vec3(dot(V, sdir), dot(V, gdir), NdotV);   // local frame: x across, y along, z = N
  float LV = lambdaAniso(Ve, as_, ag);
#else
  float var = (1.0 - s.nlen) / max(s.nlen, 0.05);       // Toksvig: filtered normal maps -> rougher
  float aT = sqrt(min(a * a + var, 1.0));
  float roughT = sqrt(aT);
#ifdef PASS_LIGHTS
  // analytic fit of the DFG terms (Karis, mobile), only used for energy compensation here
  vec4 c0_ = vec4(-1.0, -0.0275, -0.572, 0.022), c1_ = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r_ = roughT * c0_ + c1_;
  float a004_ = min(r_.x * r_.x, exp2(-9.28 * NdotV)) * r_.x + r_.y;
  vec2 dfg = vec2(-1.04, 1.04) * a004_ + r_.zw;
#else
  vec2 dfg = texture(tBRDF, vec2(NdotV, roughT)).rg;
#endif
  vec3 ms = 1.0 + F0 * (1.0 / max(dfg.x + dfg.y, 0.05) - 1.0);
#endif

  vec3 color = vec3(0.0), spec = vec3(0.0);
#ifdef PASS_LIGHTS
  // ---------------- soft boxes + accents, analytic BRDF for this frame's sample of each light
  vec3 vis3 = vec3(shadowK(0, s.P, s.Ng), shadowK(1, s.P, s.Ng), shadowK(2, s.P, s.Ng));
  vec3 E = vec3(0.0);
#ifdef ANISO
  LIGHT_ANISO(0, vis3.x, vis3.x) LIGHT_ANISO(1, vis3.y, vis3.y) LIGHT_ANISO(2, vis3.z, vis3.z)
  LIGHT_ANISO(3, ao, so) LIGHT_ANISO(4, ao, so)
#else
  LIGHT_ISO(0, vis3.x, vis3.x) LIGHT_ISO(1, vis3.y, vis3.y) LIGHT_ISO(2, vis3.z, vis3.z)
  LIGHT_ISO(3, ao, so) LIGHT_ISO(4, ao, so)
#endif
  color = diffColor / PI * E;
#else
  // ---------------- environment: SH irradiance x AO, reflections x occlusion, emission
  color = diffColor / PI * shIrr(uW2E * N) * ao;
#ifndef ANISO
  {
    vec3 R = reflect(-V, N);
    float hz = sat(1.0 + 1.3 * dot(R, s.Ng));    // reflections diving under the geometric surface
    spec = (F0 * dfg.x + dfg.y) * ms * textureLod(tEnvA, uW2E * R, roughT * uEnvLods).rgb * so * hz * hz;
  }
#else
  {
    float G1 = 1.0 / (1.0 + LV);
    vec2 rot = vec2(hash12(gl_FragCoord.xy), ign(gl_FragCoord.xy + 17.0));
    float saT = 4.0 * PI / (6.0 * uEnvRawSize * uEnvRawSize);
    for (int i = 0; i < ANISO_SAMPLES; i++) {
      vec3 h = sampleVNDF(Ve, as_, ag, fract(uXi[i] + rot));
      vec3 Ll = reflect(-Ve, h);
      if (Ll.z <= 0.0) continue;
      vec3 L = sdir * Ll.x + gdir * Ll.y + N * Ll.z;
      float VdotH = sat(dot(Ve, h));
      vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
      float w = (1.0 + LV) / (1.0 + LV + lambdaAniso(Ll, as_, ag));     // G2 / G1
      float pdf = G1 * D_aniso(h, as_, ag) / (4.0 * NdotV);
      float lod = clamp(0.5 * log2(1.0 / (uTotalSamples * pdf + 1e-6) / saT) + 1.0 + uFisBias, 0.0, 8.0);
      float hz = sat(1.0 + 1.3 * dot(L, s.Ng));
      spec += F * w * textureLod(tEnvARaw, uW2E * L, lod).rgb * hz * hz;
    }
    spec *= so / float(ANISO_SAMPLES);
  }
#endif
#endif

  vec3 diffOut = color;
  color += spec;
#ifndef PASS_LIGHTS
  color += uEmissive * (uHas.w == 1 ? texture(tEmis, vUV).rgb : vec3(1.0));
  if (uDebug == 1) color = vec3(ao);
  else if (uDebug == 2) color = N * 0.5 + 0.5;
  else if (uDebug == 3) color = s.base;
#else
  if (uDebug >= 1 && uDebug <= 3) color = vec3(0.0);
#endif
  if (uDebug == 4) color = spec;
  else if (uDebug == 5) color = diffOut;
  // the lights pass adds light only: coverage (alpha) comes from the environment pass
#ifdef PASS_LIGHTS
  if (uAlphaMode == 2) o = vec4(color * s.alpha, s.alpha);
  else o = vec4(color, 0.0);
#else
  if (uAlphaMode == 2) o = vec4(color * s.alpha, s.alpha);
  else o = vec4(color, 1.0);
#endif
}`;

  // Ground shadow catcher: black with alpha = how much of the light reaching an empty floor is blocked.
  const GROUND_FS = HEAD + COMMON + LIGHTS + `
in vec3 vWorld;
uniform sampler2D tAOG;
uniform vec2 uRes;
uniform float uEnvUp;          // irradiance from env A on an unoccluded floor (luminance)
uniform float uLEz[3];         // this frame's light irradiance on the floor (luminance * cos)
uniform float uUnshadowed;     // mean total irradiance on an unoccluded floor
uniform float uOpacity;
uniform vec3 uFadeCentre;
uniform float uFadeRadius;
uniform float uEdgeFade;       // fade the shadow out near the image border (fraction of the frame)
layout(location = 0) out vec4 o;
void main() {
  vec4 g = texelFetch(tAOG, ivec2(gl_FragCoord.xy), 0);
  float ao = g.y > 1e-4 ? g.x / g.y : 1.0;
  float lit = uEnvUp * ao;
  lit += uLEz[0] * shadowK(0, vWorld, vec3(0.0, 0.0, 1.0));
  lit += uLEz[1] * shadowK(1, vWorld, vec3(0.0, 0.0, 1.0));
  lit += uLEz[2] * shadowK(2, vWorld, vec3(0.0, 0.0, 1.0));
  float a = (1.0 - lit / uUnshadowed) * uOpacity;
  float r = length(vWorld.xy - uFadeCentre.xy) / uFadeRadius;
  a *= 1.0 - smoothstep(0.7, 1.0, r);
  vec2 q = gl_FragCoord.xy / uRes;
  float e = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
  if (uEdgeFade > 0.0) a *= smoothstep(0.0, uEdgeFade, e);
  o = vec4(0.0, 0.0, 0.0, a);
}`;

  // Fill pixels that got no phase-1 samples of a kind (object / floor) from their neighbours (up to 2 px).
  const AO_FILL_FS = HEAD + `
uniform sampler2D tObj;
uniform sampler2D tGround;
layout(location = 0) out vec4 oObj;
layout(location = 1) out vec4 oGround;
vec4 fill(sampler2D t, ivec2 p, ivec2 hi) {
  vec4 a = texelFetch(t, p, 0);
  if (a.y > 1e-4) return a;
  vec4 s = vec4(0.0);
  for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++) {
      vec4 n = texelFetch(t, clamp(p + ivec2(x, y), ivec2(0), hi), 0);
      float w = (abs(x) <= 1 && abs(y) <= 1) ? 1.0 : 0.25;
      s += n * w;
    }
  return s;
}
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  ivec2 hi = textureSize(tObj, 0) - 1;
  oObj = fill(tObj, p, hi);
  oGround = fill(tGround, p, hi);
}`;

  // ---------------------------------------------------------------- accumulation / post
  const COPY_ADD_FS = HEAD + `
uniform sampler2D tSrc;
uniform float uWeight;
out vec4 o;
void main() { o = texelFetch(tSrc, ivec2(gl_FragCoord.xy), 0) * uWeight; }`;

  // bright pass + 2x downsample of the averaged HDR (premultiplied)
  const BRIGHT_FS = HEAD + COMMON + `
uniform sampler2D tAcc;
uniform float uScale;        // exposure / frames
uniform float uThreshold;
uniform vec2 uSrcRes;
out vec4 o;
vec3 px(ivec2 p) { return texelFetch(tAcc, clamp(p, ivec2(0), ivec2(uSrcRes) - 1), 0).rgb * uScale; }
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy) * 2;
  vec3 c = (px(p) + px(p + ivec2(1, 0)) + px(p + ivec2(0, 1)) + px(p + ivec2(1, 1))) * 0.25;
  float l = max(c.r, max(c.g, c.b));
  float k = max(l - uThreshold, 0.0);
  k = k * k / (k + 0.5 * uThreshold + 1e-4);    // soft knee
  o = vec4(c * (k / max(l, 1e-4)), 1.0);
}`;

  const DOWN_FS = HEAD + `
uniform sampler2D tSrc;
uniform vec2 uSrcRes;
out vec4 o;
void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0) / uSrcRes;
  vec2 t = 1.0 / uSrcRes;
  vec3 c = texture(tSrc, uv).rgb * 0.5;
  c += texture(tSrc, uv + vec2(-t.x, -t.y)).rgb * 0.125;
  c += texture(tSrc, uv + vec2(t.x, -t.y)).rgb * 0.125;
  c += texture(tSrc, uv + vec2(-t.x, t.y)).rgb * 0.125;
  c += texture(tSrc, uv + vec2(t.x, t.y)).rgb * 0.125;
  o = vec4(c, 1.0);
}`;

  const BLUR_FS = HEAD + `
uniform sampler2D tSrc;
uniform vec2 uDir;           // texel step
uniform float uSigma;        // in texels
out vec4 o;
void main() {
  vec2 res = vec2(textureSize(tSrc, 0));
  vec2 uv = gl_FragCoord.xy / res;
  int r = int(ceil(uSigma * 3.0));
  vec3 c = vec3(0.0);
  float ws = 0.0;
  for (int i = -48; i <= 48; i++) {
    if (i < -r || i > r) continue;
    float w = exp(-0.5 * float(i * i) / (uSigma * uSigma));
    c += texture(tSrc, uv + uDir * float(i)).rgb * w;
    ws += w;
  }
  o = vec4(c / ws, 1.0);
}`;

  const FINAL_FS = HEAD + COMMON + `
uniform sampler2D tAcc;
uniform sampler2D tBloomA;
uniform sampler2D tBloomB;
uniform float uInvFrames;
uniform float uExposure;
uniform float uBloom;
uniform int uTonemap;        // 0 agx, 1 aces, 2 neutral, 3 linear clamp
uniform vec4 uBg;            // sRGB background, .a = 1 when a solid background is wanted
uniform vec2 uRes;
uniform float uDither;
out vec4 o;

vec3 agxContrast(vec3 x) {
  vec3 x2 = x * x;
  vec3 x4 = x2 * x2;
  return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}
vec3 agx(vec3 v) {
  const mat3 m = mat3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                      0.0784335999999992, 0.878468636469772, 0.0784336,
                      0.0792237451477643, 0.0791661274605434, 0.879142973793104);
  const mat3 mi = mat3(1.19687900512017, -0.0528968517574562, -0.0529716355144438,
                       -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
                       -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
  const float lo = -12.47393, hi = 4.026069;
  v = m * max(v, vec3(1e-10));
  v = clamp(log2(v), lo, hi);
  v = (v - lo) / (hi - lo);
  v = agxContrast(v);
  // gentle "punchy" look: a bit more contrast + saturation than base AgX
  float l = dot(v, vec3(0.2126, 0.7152, 0.0722));
  v = pow(max(v, vec3(0.0)), vec3(1.12));
  float l2 = dot(v, vec3(0.2126, 0.7152, 0.0722));
  v = l2 + 1.12 * (v - l2);
  v = mi * v;
  return clamp(pow(max(v, vec3(0.0)), vec3(2.2)), 0.0, 1.0);
}
vec3 aces(vec3 c) {
  const mat3 im = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
  const mat3 om = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
  c = im * (c / 0.6);
  vec3 a = c * (c + 0.0245786) - 0.000090537;
  vec3 b = c * (0.983729 * c + 0.4329510) + 0.238081;
  return clamp(om * (a / b), 0.0, 1.0);
}
vec3 neutral(vec3 c) {
  const float sc = 0.76, desat = 0.15;
  float x = min(c.r, min(c.g, c.b));
  float off = x < 0.08 ? x - 6.25 * x * x : 0.04;
  c -= off;
  float peak = max(c.r, max(c.g, c.b));
  if (peak < sc) return c;
  float d = 1.0 - sc;
  float np = 1.0 - d * d / (peak + d - sc);
  c *= np / peak;
  float g = 1.0 - 1.0 / (desat * (peak - np) + 1.0);
  return mix(c, vec3(np), g);
}
vec3 tonemap(vec3 c) {
  if (uTonemap == 0) return agx(c);
  if (uTonemap == 1) return aces(c);
  if (uTonemap == 2) return clamp(neutral(c), 0.0, 1.0);
  return clamp(c, 0.0, 1.0);
}
vec3 toSRGB(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
  vec2 uv = gl_FragCoord.xy / uRes;
  vec4 acc = texelFetch(tAcc, ivec2(gl_FragCoord.xy), 0) * uInvFrames;
  float alpha = sat(acc.a);
  vec3 hdr = acc.rgb * uExposure;
  vec3 straight = alpha > 1e-6 ? max(hdr, vec3(0.0)) / alpha : vec3(0.0);
  vec3 d = tonemap(straight);
  vec3 glow = (texture(tBloomA, uv).rgb * 0.65 + texture(tBloomB, uv).rgb * 0.35) * uBloom;
  vec3 g = 1.0 - exp(-glow);
  vec3 pm = d * alpha + g * (1.0 - 0.5 * alpha);
  float ga = max(g.r, max(g.g, g.b));
  float aOut = sat(alpha + (1.0 - alpha) * ga);
  vec3 sOut = aOut > 1e-6 ? clamp(pm / aOut, 0.0, 1.0) : vec3(0.0);
  vec3 srgb = toSRGB(sOut);
  // triangular dither (1 LSB), not on fully transparent / opaque alpha
  float n1 = hash12(gl_FragCoord.xy + 0.37) + hash12(gl_FragCoord.xy * 1.31 + 11.7) - 1.0;
  float n2 = hash12(gl_FragCoord.xy * 0.73 + 5.1) + hash12(gl_FragCoord.xy * 1.7 + 2.9) - 1.0;
  srgb += n1 * uDither / 255.0;
  float aq = aOut;
  if (aq > 0.5 / 255.0 && aq < 1.0 - 0.5 / 255.0) aq = clamp(aq + n2 * uDither / 255.0, 0.0, 1.0);
  else aq = aq < 0.5 / 255.0 ? 0.0 : 1.0;
  if (uBg.a > 0.5) {
    o = vec4(mix(uBg.rgb, clamp(srgb, 0.0, 1.0), aq), 1.0);
  } else {
    o = vec4(aq > 0.0 ? clamp(srgb, 0.0, 1.0) : vec3(0.0), aq);
  }
}`;

  root.NZ_SHADERS = {
    FULLSCREEN_VS, ENV_FS, PREFILTER_FS, BRDF_LUT_FS, MESH_VS, DEPTH_VS, DEPTH_FS,
    AO_FS, AO_GROUND_FS, AO_FILL_FS, GROUND_VS, MAIN_FS, GROUND_FS, COPY_ADD_FS, BRIGHT_FS, DOWN_FS, BLUR_FS, FINAL_FS,
  };
})(typeof window !== 'undefined' ? window : globalThis);
