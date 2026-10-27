"""Shared by the record console (nayzeee_audio_g), its platter (nayzeee_tt_platter) and tonearm
(nayzeee_tt_arm): the shared-contract geometry, small mesh helpers and the turntable-lane
materials / textures.  Not a model (the registry ignores files starting with "_").

All numbers below are the HARD contract (see scratchpad plan/CONTRACT.md, "Turntable geometry");
gameplay code (client/turntable.lua) is written against them.  Console space: origin = floor centre
under the cabinet, +Y = front, +X = viewer's left, +Z up.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from lib import materials as mats
from lib import mesh as M
from lib import textures as tx
from lib.materials import PBR, Material

# --------------------------------------------------------------------------- contract (console space, metres)
CAB_X = (-0.50, 0.50)
CAB_Y = (-0.21, 0.21)
LEG_TOP = 0.38                          # legs end / cabinet body starts
CAB_TOP = 0.74                          # walnut top surface
PLINTH_X = (0.02, 0.48)                 # deck plinth on the viewer's LEFT half (+X)
PLINTH_Y = (-0.19, 0.19)
DECK_TOP = 0.785                        # deck top surface (platter sits here)
PANEL_X = (-0.48, -0.02)                # control panel on the viewer's RIGHT half (-X), mirrors the plinth

PLATTER_OFFSET = (0.300, 0.000, 0.785)  # platter origin = centre of its bottom face
PLATTER_R = 0.160
SLIPMAT_TOP = 0.026                     # platter-local: record bottom sits here (console z 0.811)
SPINDLE_R = 0.0035
SPINDLE_TOP = 0.040                     # platter-local

RECORD_OFFSET = (0.300, 0.000, 0.811)   # nayzeee_vinyl origin = centre of its bottom face
RECORD_R = 0.1515
RECORD_T = 0.0022
LABEL_R = 0.050
HOLE_R = 0.0037

ARM_OFFSET = (0.075, -0.125, 0.835)     # tonearm origin = pivot point
ARM_LEN = 0.250
STYLUS_LOCAL = (0.000, 0.250, -0.022)   # arm-local stylus tip (rotation 0 = arm along +Y)
ARM_REST_XY = (0.075, 0.100)            # console xy where the rest post holds the arm tube
ARM_REST_TOP = 0.835 - 0.010            # top of the rest (= bottom of the arm tube when parked)
LEAD_IN = 0.146
RUN_OUT = 0.062
SPIN_DEG_S = 200.0                      # 33 1/3 rpm
ARM_LIFT_DEG = 3.0                      # gameplay lifts the tip 2-4 deg (positive rotation about local X)

# arm tube (arm-local): its bottom rests on the rest post top
ARM_TUBE_R = 0.0040
ARM_TUBE_Z = ARM_REST_TOP - ARM_OFFSET[2] + ARM_TUBE_R          # -0.006
ARM_REST_LOCAL_Y = ARM_REST_XY[1] - ARM_OFFSET[1]                 # 0.225 along the arm

PIVOT_TO_CENTRE = math.hypot(PLATTER_OFFSET[0] - ARM_OFFSET[0], PLATTER_OFFSET[1] - ARM_OFFSET[1])  # 0.2574


def arm_angle(r: float) -> float:
    """Arm rotation about Z (degrees, negative = over the record) that puts the stylus at groove radius r."""
    px, py = PLATTER_OFFSET[0] - ARM_OFFSET[0], PLATTER_OFFSET[1] - ARM_OFFSET[1]
    d, L = PIVOT_TO_CENTRE, ARM_LEN
    toward_centre = math.degrees(math.atan2(-px, py))          # rotation that points the arm at the spindle
    phi = math.degrees(math.acos((d * d + L * L - r * r) / (2 * d * L)))
    return toward_centre + phi


# --------------------------------------------------------------------------- mesh helpers
def along(mesh: M.Mesh, p0, p1) -> M.Mesh:
    """Map a part built along local +Z (from z = 0) onto the segment p0 -> p1 (z axis -> p1 - p0)."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    d = d / np.linalg.norm(d)
    z = np.array([0.0, 0.0, 1.0])
    ax = np.cross(z, d)
    s = float(np.linalg.norm(ax))
    if s < 1e-9:
        R = np.eye(3) if d[2] > 0 else M.rotation_matrix("x", 180.0)
    else:
        R = M.rotation_matrix(ax / s, math.degrees(math.atan2(s, float(np.dot(z, d)))))
    return mesh.transform(M.compose(M.translation_matrix(p0), R))


def facing(mesh: M.Mesh, direction, cos_min: float = 0.95):
    """Split a mesh by triangle orientation -> (triangles facing ``direction``, the rest)."""
    P, F = mesh.positions, mesh.indices
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-18)
    sel = n @ np.asarray(direction, float) >= cos_min

    def sub(mask):
        m = mesh.copy()
        m.indices = F[mask].copy()
        m.tangents = None
        return m.compact()
    return sub(sel), sub(~sel)


def hull_2d(points) -> np.ndarray:
    """Convex hull (CCW) of 2D points (monotone chain)."""
    P = sorted(set((round(float(x), 9), round(float(y), 9)) for x, y in points))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in P:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(P):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1], float)


def rotate_2d(points, degrees: float, origin=(0.0, 0.0)) -> np.ndarray:
    """Rotate 2D points counter-clockwise by ``degrees`` about ``origin``."""
    t = math.radians(degrees)
    c, s = math.cos(t), math.sin(t)
    p = np.asarray(points, float) - np.asarray(origin, float)
    return p @ np.array([[c, s], [-s, c]]) + np.asarray(origin, float)


def fillet_2d(points, radius: float, segments: int = 3, only=None) -> np.ndarray:
    """Round the corners of a closed 2D polygon with arcs of ``radius`` (clamped to the edge lengths).
    ``only``: indices of the corners to round (default all)."""
    P = np.asarray(points, float)
    n = len(P)
    seg = M.seg(segments, 1)
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        if only is not None and i not in only:
            out.append(b)
            continue
        u, v = a - b, c - b
        lu, lv = np.linalg.norm(u), np.linalg.norm(v)
        u, v = u / lu, v / lv
        ang = math.acos(float(np.clip(np.dot(u, v), -1.0, 1.0)))
        if ang < 1e-3 or abs(ang - math.pi) < 1e-3:
            out.append(b)
            continue
        t = min(radius / math.tan(ang / 2), lu * 0.45, lv * 0.45)
        r = t * math.tan(ang / 2)
        p0, p1 = b + u * t, b + v * t
        bis = (u + v) / np.linalg.norm(u + v)
        cc = b + bis * (r / math.sin(ang / 2))
        a0 = math.atan2(*(p0 - cc)[::-1])
        a1 = math.atan2(*(p1 - cc)[::-1])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(seg + 1):
            t_ = a0 + da * k / seg
            out.append(cc + r * np.array([math.cos(t_), math.sin(t_)]))
    return np.array(out)


def knurled_ring(r_out: float, r_in: float, h: float, segments: int = 48, chamfer: float = 0.0005):
    """Ring around Z from z 0 to h: a diamond-knurled band with smooth spun-aluminium chamfers and end
    faces (the knurl is never stretched across the flat faces).  No inner wall: it sits on a shaft of
    radius r_in."""
    c = chamfer
    band = M.lathe([(r_out, c, 1.0, 0.0), (r_out, h - c, 1.0, 0.0)], segments, material="tt_alu_knurl")
    band = band.uv_cylindrical("z")
    low = M.lathe([(r_in, 0.0, 0.0, -1.0), (r_out - c, 0.0, 0.0, -1.0), (r_out, c)], segments, crease=50,
                  material="brushed_aluminium_radial").uv_radial(r_out)
    top = M.lathe([(r_out, h - c), (r_out - c, h, 0.0, 1.0), (r_in, h, 0.0, 1.0)], segments, crease=50,
                  material="brushed_aluminium_radial").uv_radial(r_out)
    return [band, low, top]


DECAL_OFF = 0.0005                     # printed decals float this far above their surface (no z-fighting)


def decal(entry: str, width: float, center, facing_dir="+z", material: str = "print_decal", rotate=0.0,
          height: float | None = None):
    """A print-atlas decal quad: ``width`` along the image u axis (or give ``height`` instead, e.g. so
    labels share one cap height), the other side from the entry's aspect ratio."""
    if height is not None:
        width = height * tx.atlas_aspect(entry)
    h = width / tx.atlas_aspect(entry)
    m = M.plane(width, h, center=(0, 0, 0), facing="design", rect=tx.atlas_rect(entry), material=material)
    if rotate:
        m = m.rotate_z(rotate)
    return m.orient(facing_dir, center)


def uv_around(mesh: M.Mesh, repeats: float, z0: float, z1: float, center=(0.0, 0.0)) -> M.Mesh:
    """UVs for a lathe band around Z: u = angle * repeats / 360 deg (continuous over the lathe seam
    column), v = 0 at z1 (top of the image) .. 1 at z0."""
    m = mesh.copy()
    p = m.positions
    ang = np.degrees(np.arctan2(p[:, 1] - center[1], p[:, 0] - center[0])) % 360.0
    # lathe seam: the last column repeats angle 0 at 360
    seam = (ang < 1e-6) & (m.uvs[:, 0] > 1e-9)
    ang[seam] = 360.0
    m.uvs = np.column_stack([ang / 360.0 * repeats, (z1 - p[:, 2]) / (z1 - z0)])
    m.uv_tile = None
    m.tangents = None
    return m


# --------------------------------------------------------------------------- materials / textures
def _tex(name, size, fmt="DXT1", kind="color", description=""):
    """textures.register that tolerates a module reload."""
    def deco(fn):
        if not tx.exists(name):
            tx.register(name, size, fmt, kind, description)(fn)
        return fn
    return deco


def _mat(mat: Material) -> Material:
    if mat.name in mats.names():
        return mats.get(mat.name)
    return mats.register(mat)


def _ns(name, d, n, s, tile, pbr, collision, description, **params):
    return _mat(Material(name, "normal_spec", {"DiffuseSampler": d, "BumpSampler": n, "SpecSampler": s},
                         params, pbr, tile, collision, description))


def _brushed_strip(w, h, v0=0.0):
    """A w x h crop of the shared brushed-aluminium base colour (brushing along U), same texel scale."""
    src = np.asarray(tx.image("nz_brushed_d"), np.float32)
    sh, sw = src.shape[:2]
    rows = (np.arange(h) + int(v0 * sh)) % sh
    cols = np.arange(w) % sw
    return src[rows][:, cols, :3]


@_tex("nz_tt_brass_d", 256, description="Brushed brass (leg ferrules), brushing along U.")
def _brass_d(w, h):
    a = _brushed_strip(w, h)
    lum = a.mean(axis=2, keepdims=True)
    brass = tx.hex_rgb("#c9a45c")[None, None, :]
    return np.clip(brass * (0.55 + 0.6 * lum), 0, 1)


STROBE_REPEATS = 9                     # texture repeats around the platter rim
STROBE_ROWS = (20, 24, 15, 18)         # dots per repeat -> 180 / 216 / 135 / 162 around


def _strobe_fields(w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    hm = np.zeros((h, w))
    ink = np.zeros((h, w))
    rows = len(STROBE_ROWS)
    rh = h / (rows + 0.4)
    r_px = rh * 0.30
    for k, n in enumerate(STROBE_ROWS):
        cy = rh * (k + 0.7)
        pitch = w / n
        dx = ((xx + pitch / 2) % pitch) - pitch / 2
        d = np.sqrt((dx / 1.0) ** 2 + (yy - cy) ** 2)
        dome = np.clip(1 - (d / r_px) ** 2, 0, 1)
        hm = np.maximum(hm, np.sqrt(dome))
        ink = np.maximum(ink, 1 - tx.smoothstep(r_px * 0.8, r_px * 1.05, d))
    # two fine machined grooves between the dot rows and the rim edges
    for gy in (rh * 0.15, h - rh * 0.1):
        hm -= 0.6 * np.exp(-((yy - gy) / 0.8) ** 2)
    return hm, ink


@_tex("nz_tt_strobe_d", (512, 64), description="Platter rim: brushed aluminium with four rows of strobe dots "
                                               "(9 repeats around the rim).")
def _strobe_d(w, h):
    base = _brushed_strip(w, h, 0.37)
    hm, ink = _strobe_fields(w, h)
    dot = tx.hex_rgb("#5d6267")[None, None, :]
    k = 0.65 * ink[:, :, None]                     # machined bumps, a shade darker than the rim (not holes)
    c = base * (1 - k) + dot * k
    return np.clip(c, 0, 1)


@_tex("nz_tt_strobe_n", (512, 64), kind="normal", description="Platter rim strobe dots (raised) + grooves.")
def _strobe_n(w, h):
    hm, ink = _strobe_fields(w, h)
    return tx.height_to_normal(hm, 1.2, wrap=True)


def _slipmat_fibres(w, h, seed=211):
    """Felt fibres for a 0.30 m slipmat mapped 1:1 (about 0.6 mm per texel)."""
    ss = 2
    W, H = w * ss, h * ss
    img = Image.new("L", (W, H), 128)
    d = ImageDraw.Draw(img)
    r = tx.rng(seed)
    for _ in range(int(w * h / 7)):
        x, y = r.uniform(0, W), r.uniform(0, H)
        ang = r.uniform(0, math.pi)
        ln = r.uniform(1.5, 5.0) * ss
        bend = r.uniform(-0.5, 0.5)
        pts = [(x + math.cos(ang + bend * t) * ln * t, y + math.sin(ang + bend * t) * ln * t)
               for t in (0.0, 0.34, 0.67, 1.0)]
        d.line(pts, fill=int(r.uniform(60, 210)), width=1)
    a = np.asarray(img.reduce(ss), dtype=np.float64) / 255.0
    return tx.standardize(tx.blur(a, 0.5))


def _slipmat_print(S):
    """Print layer (RGBA, S x S): thin teal ring, tracked arc text, a small mark -- subtle on felt."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    R = S / 2                                    # = slipmat radius 0.150
    teal = tuple(int(v * 255) for v in tx.hex_rgb(tx.TEAL))
    for rad, wd, col in ((0.955, 0.006, teal + (150,)), (0.935, 0.0025, (120, 126, 130, 90)),
                         (0.43, 0.0025, (120, 126, 130, 70))):
        r0 = rad * R
        d.ellipse([c - r0, c - r0, c + r0, c + r0], outline=col, width=max(1, int(wd * S)))
    tx.arc_text(img, c, c, 0.875 * R, "NAYZEEE  AUDIO   ·   HIGH FIDELITY   ·   33 / 45 RPM   ·   RECORD CONSOLE",
                0.028 * S, 500, (128, 134, 138, 150), -90, 0.22)
    tx.arc_text(img, c, c, 0.875 * R, "·   MODEL G   ·", 0.028 * S, 500, teal + (170,), 90, 0.22)
    ms = 0.085 * S
    tx.draw_mark(img, c - ms / 2, c + 0.60 * R - ms / 2, ms, "white")
    a = np.asarray(img, np.float32) / 255.0
    a[:, :, 3] *= np.where(np.all(a[:, :, :3] > 0.9, axis=2), 0.16, 1.0)      # the white mark: faint
    return a


@_tex("nz_tt_slipmat_d", 512, description="Black felt slipmat with a subtle print (map with uv_radial(0.150)).")
def _slipmat_d(w, h):
    f = _slipmat_fibres(w, h)
    tone = 1 + 0.13 * f + 0.05 * tx.fbm(w, h, 3, 4, seed=212)
    base = tx.hex_rgb("#151618")[None, None, :] * tone[:, :, None]
    ss = 2
    pr = _slipmat_print(w * ss)
    pr = np.asarray(Image.fromarray((pr * 255).astype(np.uint8), "RGBA").reduce(ss), np.float32) / 255.0
    ink = pr[:, :, 3:4] * np.clip(0.8 + 0.25 * f[:, :, None], 0, 1)          # print soaks into the fibres
    return np.clip(base * (1 - ink) + pr[:, :, :3] * 0.8 * ink, 0, 1)


@_tex("nz_tt_slipmat_n", 512, kind="normal", description="Slipmat felt fibre relief (uv_radial over the mat).")
def _slipmat_n(w, h):
    return tx.height_to_normal(tx.blur(_slipmat_fibres(w, h), 0.7), 0.35)


def _plate_fields(w, h):
    """Engraving mask for the console name plate (1 = engraved)."""
    ss = 4
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    W, H = w * ss, h * ss
    tx.draw_text(d, (W * 0.565, H * 0.43), "NAYZEEE", H * 0.36, 600, 255, "mm", 0.42)
    tx.draw_text(d, (W * 0.565, H * 0.77), "RECORD CONSOLE  ·  MODEL G", H * 0.12, 500, 255, "mm", 0.3)
    m = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tx.draw_mark(m, W * 0.045, H * 0.2, H * 0.6, "white")
    img = Image.fromarray(np.maximum(np.asarray(img), np.asarray(m)[:, :, 3]))
    d = ImageDraw.Draw(img)
    for x in (W * 0.012, W * 0.988):                           # two fine border lines
        d.line([(x, H * 0.12), (x, H * 0.88)], fill=160, width=ss)
    return np.asarray(img.reduce(ss), np.float64) / 255.0


@_tex("nz_tt_plate_d", (512, 128), description="Console name plate: brushed aluminium, engraved NAYZEEE.")
def _plate_d(w, h):
    base = _brushed_strip(w, h, 0.61) * 1.04
    e = _plate_fields(w, h)[:, :, None]
    return np.clip(base * (1 - e) + tx.hex_rgb("#1b1d20")[None, None, :] * e, 0, 1)


@_tex("nz_tt_plate_n", (512, 128), kind="normal", description="Console name plate engraving.")
def _plate_n(w, h):
    return tx.height_to_normal(-tx.blur(_plate_fields(w, h), 0.6), 1.5, wrap=False)


# --- materials (names prefixed tt_ so they never clash with other lanes) ---------------------
_ns("tt_lacquer_black", "nz_plastic_black_d", "nz_plastic_n", "nz_plastic_s", 0.12,
    PBR(roughness=0.3), "WOOD_SOLID_POLISHED", "Satin black lacquer (console legs).",
    specularIntensityMult=0.6, specularFalloffMult=120.0, specularFresnel=0.94, bumpiness=0.25)
_ns("tt_brass", "nz_tt_brass_d", "nz_brushed_n", "nz_brushed_s", 0.15,
    PBR(metallic=1.0, roughness=0.3), "METAL_SOLID_SMALL", "Brushed brass (leg ferrules).",
    specularIntensityMult=1.0, specularFalloffMult=150.0, specularFresnel=0.97, bumpiness=0.5)
KNOB_R = 0.0195
_ns("tt_alu_knurl", "nz_brushed_d", "nz_rubber_knurl_n", "nz_brushed_s", 2 * math.pi * KNOB_R / 4,
    PBR(metallic=1.0, roughness=0.36), "METAL_SOLID_SMALL",
    "Diamond-knurled aluminium (knob grips, counterweight ring); tile = a quarter of a 19.5 mm knob's circumference.",
    specularIntensityMult=0.9, specularFalloffMult=120.0, specularFresnel=0.96, bumpiness=1.0)
_ns("tt_platter_strobe", "nz_tt_strobe_d", "nz_tt_strobe_n", "nz_brushed_s", 1.0,
    PBR(metallic=1.0, roughness=0.3), "METAL_SOLID_SMALL",
    "Platter rim with strobe dots; map with uv_around(STROBE_REPEATS).",
    specularIntensityMult=1.0, specularFalloffMult=160.0, specularFresnel=0.97, bumpiness=1.0)
_ns("tt_slipmat", "nz_tt_slipmat_d", "nz_tt_slipmat_n", "nz_spec_low", 1.0,
    PBR(roughness=1.0), "CARPET_SOLID", "Printed black felt slipmat; map with uv_radial(0.150).",
    specularIntensityMult=0.05, specularFalloffMult=4.0, specularFresnel=0.6, bumpiness=1.0)
_ns("tt_plate", "nz_tt_plate_d", "nz_tt_plate_n", "nz_brushed_s", 1.0,
    PBR(metallic=1.0, roughness=0.32), "METAL_SOLID_SMALL", "Engraved console name plate (UV 0..1, 4:1).",
    specularIntensityMult=1.0, specularFalloffMult=150.0, specularFresnel=0.97, bumpiness=1.0)

# renderer-only hints for these materials (see render/materials.json): python3 render.py --materials <this>
RENDER_HINTS = {
    "tt_brass": {"anisotropy": {"mode": "tangent", "strength": 0.8, "roughness_across": 0.5}},
    "tt_platter_strobe": {"anisotropy": {"mode": "tangent", "strength": 0.8, "roughness_across": 0.5}},
    "tt_plate": {"anisotropy": {"mode": "tangent", "strength": 0.7, "roughness_across": 0.5}},
}
