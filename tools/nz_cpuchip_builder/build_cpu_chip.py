#!/usr/bin/env python3
"""
nz_cpuchip builder
==================

Generates everything for the `nz_prop_cpu_chip` FiveM prop from scratch:

  * a procedural low-poly CPU chip mesh (PCB substrate, integrated heat spreader
    with lever tabs, bevelled lid, SMD capacitors)
  * diffuse / normal / specular textures with full mip chains as DDS
  * CodeWalker XML:  nz_prop_cpu_chip.ydr.xml  (embedded textures + collision)
                     nz_prop_cpu_chip.ytyp.xml (archetype definition)
  * preview assets:  mesh.json + PNG textures (for tools/nz_cpuchip_builder/preview)
                     nz_prop_cpu_chip.glb      (open in Blender / any glTF viewer)

The XML is converted to the binary .ydr/.ytyp that FiveM streams either with
CodeWalker (RPF Explorer -> right click -> Import XML) or with tools/cwtool.

Only numpy + Pillow are needed:  pip install numpy pillow

Coordinate system: GTA V (metres, X east, Y north, Z up).  The prop origin is at
the centre of the bottom face so PlaceObjectOnGroundProperly() works.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import struct
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ----------------------------------------------------------------------------
# configuration
# ----------------------------------------------------------------------------
PROP_NAME = "nz_prop_cpu_chip"
YTYP_NAME = "nz_cpuchip"

# dimensions (metres). Real LGA desktop CPUs are ~37-45 mm; the prop is a touch
# oversized so it reads well in game.
SUB_W = 0.050          # substrate (green PCB) width / depth
SUB_T = 0.0016         # substrate thickness
SUB_CHAMFER = 0.0035   # corner cut (pin-1 style corners)
IHS_FLANGE_W = 0.037   # IHS base plate width
IHS_FLANGE_T = 0.0008  # IHS base plate thickness
IHS_TAB_W = 0.010      # lever tab width (along the edge)
IHS_TAB_D = 0.0035     # how far the tabs stick out past the flange
IHS_CORE_W = 0.0315    # raised lid width
IHS_CORE_H = 0.0028    # raised lid height above the flange
IHS_BEVEL = 0.0007     # lid top edge bevel
CAP_L = 0.0017         # SMD capacitor length (along X)
CAP_W = 0.0009         # SMD capacitor width
CAP_H = 0.0007         # SMD capacitor height
CAP_ROW_Y = 0.0217     # capacitor rows at +/- this Y
CAP_XS = [-0.0120 + i * 0.0030 for i in range(9)]

TEX_SIZE = 1024        # diffuse atlas
NRM_SIZE = 512         # normal map (downsampled from the diffuse atlas)
SPEC_SIZE = 512        # specular map

# atlas regions in pixels of the TEX_SIZE atlas: (x0, y0, x1, y1), v grows DOWN.
R_IHS_TOP = (8, 8, 504, 504)
R_SUB_TOP = (520, 8, 1016, 504)
R_SUB_BOT = (8, 520, 504, 1016)
R_PCB_EDGE = (520, 520, 1016, 568)
R_METAL_SIDE = (520, 584, 1016, 632)
R_METAL_FLAT = (520, 648, 760, 888)
R_CAP_BODY = (776, 648, 840, 712)
R_CAP_END = (856, 648, 920, 712)
UV_INSET = 4.0         # pixels kept away from region borders (mip bleed)

PCB_GREEN = (24, 82, 46)
PCB_GREEN_DARK = (18, 64, 36)
PCB_TRACE = (44, 118, 66)
GOLD = (214, 172, 58)
GOLD_DARK = (168, 128, 36)
NICKEL = (176, 178, 182)
NICKEL_DARK = (118, 120, 124)
CAP_TAN = (156, 118, 82)
CAP_SILVER = (196, 198, 202)
SILK_WHITE = (226, 228, 222)

# fonts ship in ./fonts (DejaVu, free licence); the system copy is the fallback
_FONT_DIRS = [os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts"), "/usr/share/fonts/truetype/dejavu"]
FONT_BOLD = "DejaVuSans-Bold.ttf"
FONT_MONO = "DejaVuSansMono.ttf"
FONT_REG = "DejaVuSans.ttf"

COMPOSITE_FLAGS1 = "MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE"
COMPOSITE_FLAGS2 = ("VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, "
                    "PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, "
                    "TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS")
COLLISION_MATERIAL_INDEX = 86   # PLASTIC (materials.dat index, see Sollumz collision_materials)


# ----------------------------------------------------------------------------
# small vector helpers
# ----------------------------------------------------------------------------
def v3(x, y, z):
    return np.array((x, y, z), dtype=np.float64)


def normalize(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def f6(x: float) -> str:
    s = f"{x:.6f}"
    return "0.000000" if s == "-0.000000" else s


# ----------------------------------------------------------------------------
# mesh
# ----------------------------------------------------------------------------
@dataclass
class Mesh:
    positions: list = field(default_factory=list)
    normals: list = field(default_factory=list)
    uvs: list = field(default_factory=list)
    tangents: list = field(default_factory=list)   # (x, y, z, w)
    indices: list = field(default_factory=list)

    def add_face(self, pts, uvs):
        """Add a planar convex polygon.  `pts` must be counter-clockwise when
        seen from outside (front faces are CCW, like Blender/Sollumz).  UVs are in
        0..1 texture space with v growing downwards (DirectX / GTA convention)."""
        assert len(pts) == len(uvs) and len(pts) >= 3
        p0, p1, p2 = (np.asarray(p, dtype=np.float64) for p in pts[:3])
        n = normalize(np.cross(p1 - p0, p2 - p0))
        # tangent frame from the first triangle: T = dP/du, B = dP/dv
        e1, e2 = p1 - p0, p2 - p0
        d1 = np.subtract(uvs[1], uvs[0])
        d2 = np.subtract(uvs[2], uvs[0])
        det = d1[0] * d2[1] - d2[0] * d1[1]
        if abs(det) < 1e-14:
            t = normalize(e1)
            b = np.cross(n, t)
        else:
            t = (e1 * d2[1] - e2 * d1[1]) / det
            b = (e2 * d1[0] - e1 * d2[0]) / det
        t = normalize(t - n * np.dot(n, t))
        # GTA/CodeWalker reconstruct the bitangent as cross(T, N) * w
        w = 1.0 if np.dot(np.cross(t, n), b) >= 0.0 else -1.0
        base = len(self.positions)
        for p, uv in zip(pts, uvs):
            self.positions.append(np.asarray(p, dtype=np.float64))
            self.normals.append(n)
            self.uvs.append((float(uv[0]), float(uv[1])))
            self.tangents.append((t[0], t[1], t[2], w))
        for i in range(1, len(pts) - 1):
            self.indices.extend((base, base + i, base + i + 1))

    def bbox(self):
        p = np.asarray(self.positions)
        return p.min(axis=0), p.max(axis=0)


def uv_rect(rect, fu, fv, inset=UV_INSET, tex=TEX_SIZE):
    """Map (fu, fv) in [0,1]^2 into an atlas rect (pixels, v down) -> (u, v) in [0,1]."""
    x0, y0, x1, y1 = rect
    x0, y0, x1, y1 = x0 + inset, y0 + inset, x1 - inset, y1 - inset
    return ((x0 + fu * (x1 - x0)) / tex, (y0 + fv * (y1 - y0)) / tex)


def topdown_uv(rect, x, y, half, inset=UV_INSET):
    """UV for a point (x, y) on a horizontal square face of half-width `half`,
    drawn in the texture as a top-down view (image up = +Y)."""
    return uv_rect(rect, (x + half) / (2 * half), (half - y) / (2 * half), inset)


def add_side_strip(mesh, a, b, z0, z1, rect, u_scale=1.0, u_offset=0.0):
    """Vertical quad between 2D points a -> b (CCW order of the outline) from z0 to z1."""
    pa0 = v3(a[0], a[1], z0)
    pb0 = v3(b[0], b[1], z0)
    pb1 = v3(b[0], b[1], z1)
    pa1 = v3(a[0], a[1], z1)
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    fu0, fu1 = u_offset, u_offset + length * u_scale
    mesh.add_face(
        [pa0, pb0, pb1, pa1],
        [uv_rect(rect, fu0, 1.0), uv_rect(rect, fu1, 1.0), uv_rect(rect, fu1, 0.0), uv_rect(rect, fu0, 0.0)],
    )


def add_box(mesh, xmin, xmax, ymin, ymax, zmin, zmax, top_rect, side_rect, end_rect=None,
            bottom=False, top_uv_mode="fit"):
    """Axis aligned box. Side faces use side_rect (ends optionally end_rect)."""
    hx, hy = (xmax - xmin) / 2, (ymax - ymin) / 2
    cx, cy = (xmin + xmax) / 2, (ymin + ymax) / 2
    # top (CCW from +Z)
    tl = [v3(xmin, ymin, zmax), v3(xmax, ymin, zmax), v3(xmax, ymax, zmax), v3(xmin, ymax, zmax)]
    if top_uv_mode == "fit":
        tuv = [uv_rect(top_rect, 0, 1), uv_rect(top_rect, 1, 1), uv_rect(top_rect, 1, 0), uv_rect(top_rect, 0, 0)]
    else:  # "topdown": the rect depicts the whole parent square of half width top_uv_mode
        half = top_uv_mode
        tuv = [topdown_uv(top_rect, p[0], p[1], half) for p in tl]
    mesh.add_face(tl, tuv)
    if bottom:
        bl = [v3(xmin, ymax, zmin), v3(xmax, ymax, zmin), v3(xmax, ymin, zmin), v3(xmin, ymin, zmin)]
        mesh.add_face(bl, [uv_rect(top_rect, 0, 0), uv_rect(top_rect, 1, 0), uv_rect(top_rect, 1, 1), uv_rect(top_rect, 0, 1)])
    outline = [(xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax)]
    longest = max(hx, hy) * 2
    for i in range(4):
        a, b = outline[i], outline[(i + 1) % 4]
        is_end = (i % 2 == 1) if hx >= hy else (i % 2 == 0)
        rect = end_rect if (end_rect is not None and is_end) else side_rect
        add_side_strip(mesh, a, b, zmin, zmax, rect, u_scale=1.0 / longest if rect is side_rect else 1.0 / (2 * min(hx, hy)))


def build_mesh() -> Mesh:
    m = Mesh()
    hw = SUB_W / 2
    c = SUB_CHAMFER
    zs = SUB_T

    # --- substrate: octagonal prism (chamfered square) -------------------------
    octagon = [(hw - c, -hw), (hw, -hw + c), (hw, hw - c), (hw - c, hw),
               (-hw + c, hw), (-hw, hw - c), (-hw, -hw + c), (-hw + c, -hw)]
    top = [v3(x, y, zs) for x, y in octagon]
    m.add_face(top, [topdown_uv(R_SUB_TOP, x, y, hw) for x, y in octagon])
    bottom = [v3(x, y, 0.0) for x, y in reversed(octagon)]
    m.add_face(bottom, [topdown_uv(R_SUB_BOT, x, y, hw) for x, y in reversed(octagon)])
    for i in range(8):
        a, b = octagon[i], octagon[(i + 1) % 8]
        add_side_strip(m, a, b, 0.0, zs, R_PCB_EDGE, u_scale=1.0 / SUB_W)

    # --- IHS flange plate + lever tabs ---------------------------------------
    fhw = IHS_FLANGE_W / 2
    zf = zs + IHS_FLANGE_T
    add_box(m, -fhw, fhw, -fhw, fhw, zs, zf, R_METAL_FLAT, R_METAL_SIDE, top_uv_mode="fit")
    thw = IHS_TAB_W / 2
    add_box(m, fhw, fhw + IHS_TAB_D, -thw, thw, zs, zf, R_METAL_FLAT, R_METAL_SIDE)
    add_box(m, -fhw - IHS_TAB_D, -fhw, -thw, thw, zs, zf, R_METAL_FLAT, R_METAL_SIDE)

    # --- IHS lid: sides, bevel ring, top -------------------------------------
    chw = IHS_CORE_W / 2
    b = IHS_BEVEL
    z_top = zf + IHS_CORE_H
    z_bev = z_top - b
    outline = [(-chw, -chw), (chw, -chw), (chw, chw), (-chw, chw)]
    inner = [(-chw + b, -chw + b), (chw - b, -chw + b), (chw - b, chw - b), (-chw + b, chw - b)]
    for i in range(4):
        a, bb = outline[i], outline[(i + 1) % 4]
        add_side_strip(m, a, bb, zf, z_bev, R_METAL_SIDE, u_scale=1.0 / IHS_CORE_W)
        ia, ib = inner[i], inner[(i + 1) % 4]
        pts = [v3(a[0], a[1], z_bev), v3(bb[0], bb[1], z_bev), v3(ib[0], ib[1], z_top), v3(ia[0], ia[1], z_top)]
        m.add_face(pts, [uv_rect(R_METAL_SIDE, 0, 1), uv_rect(R_METAL_SIDE, 1, 1),
                         uv_rect(R_METAL_SIDE, 1, 0.75), uv_rect(R_METAL_SIDE, 0, 0.75)])
    ihw = chw - b
    lid = [v3(x, y, z_top) for x, y in inner]
    m.add_face(lid, [topdown_uv(R_IHS_TOP, x, y, ihw) for x, y in inner])

    # --- SMD capacitors on the substrate ---------------------------------------
    for sy in (-1, 1):
        for x in CAP_XS:
            y = sy * CAP_ROW_Y
            add_box(m, x - CAP_L / 2, x + CAP_L / 2, y - CAP_W / 2, y + CAP_W / 2, zs, zs + CAP_H,
                    R_CAP_BODY, R_CAP_BODY, end_rect=R_CAP_END)
    return m


def cap_footprints():
    """Capacitor footprints as (xmin, xmax, ymin, ymax) in metres (for the texture)."""
    out = []
    for sy in (-1, 1):
        for x in CAP_XS:
            y = sy * CAP_ROW_Y
            out.append((x - CAP_L / 2, x + CAP_L / 2, y - CAP_W / 2, y + CAP_W / 2))
    return out


# ----------------------------------------------------------------------------
# textures
# ----------------------------------------------------------------------------
_font_warned = set()


def font(name, size):
    for d in _FONT_DIRS:
        path = os.path.join(d, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    if name not in _font_warned:
        _font_warned.add(name)
        print(f"WARNING: font {name} not found in {_FONT_DIRS}; markings will use Pillow's default font "
              f"and the textures will differ from dist/")
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def brushed(h, w, rng, window=31, amp=1.0):
    """Horizontal brushed-metal streak noise in [-amp, amp]-ish."""
    n = rng.standard_normal((h, w)).astype(np.float32)
    pad = np.pad(n, ((0, 0), (window, 0)))
    cs = np.cumsum(pad, axis=1)
    s = (cs[:, window:] - cs[:, :-window]) / window
    s = s / (s.std() + 1e-6)
    return s * amp


def region_slices(rect):
    x0, y0, x1, y1 = rect
    return slice(y0, y1), slice(x0, x1)


def metres_to_px(rect, x, y, half):
    """Top-down mapping of a point on a square face into pixel coords of a rect."""
    x0, y0, x1, y1 = rect
    fu = (x + half) / (2 * half)
    fv = (half - y) / (2 * half)
    return x0 + fu * (x1 - x0), y0 + fv * (y1 - y0)


ATLAS_REGIONS = [R_IHS_TOP, R_SUB_TOP, R_SUB_BOT, R_PCB_EDGE, R_METAL_SIDE, R_METAL_FLAT, R_CAP_BODY, R_CAP_END]


def fill_gutters(arrays, painted):
    """Flood the unpainted atlas pixels (gutters, unused space) with the nearest painted
    values so lower mip levels do not average region borders against black."""
    todo = ~painted
    if not todo.any():
        return
    cur = [a.copy() for a in arrays]
    done = painted.copy()
    for _ in range(max(arrays[0].shape[:2])):
        if not (~done).any():
            break
        new_done = done.copy()
        for shift, axis in ((1, 0), (-1, 0), (1, 1), (-1, 1)):
            src_done = np.roll(done, shift, axis=axis)
            take = (~new_done) & src_done
            if not take.any():
                continue
            for a in cur:
                a[take] = np.roll(a, shift, axis=axis)[take]
            new_done |= take
        done = new_done
    for a, c in zip(arrays, cur):
        a[...] = c


class Atlas:
    def __init__(self, size):
        self.size = size
        self.diffuse = np.zeros((size, size, 3), np.float32)
        self.height = np.zeros((size, size), np.float32)
        self.spec = np.zeros((size, size), np.float32)
        self.metal = np.zeros((size, size), np.float32)   # for the glTF preview only
        self.rng = np.random.default_rng(1337)

    def painted_mask(self):
        m = np.zeros((self.size, self.size), bool)
        for rect in ATLAS_REGIONS:
            ys, xs = region_slices(rect)
            m[ys, xs] = True
        return m

    # helpers -----------------------------------------------------------
    def fill(self, rect, color, spec, metal=0.0):
        ys, xs = region_slices(rect)
        self.diffuse[ys, xs] = color
        self.spec[ys, xs] = spec
        self.metal[ys, xs] = metal

    def paint_metal(self, rect, base=NICKEL, amp=3.5, spec=0.78):
        ys, xs = region_slices(rect)
        h, w = ys.stop - ys.start, xs.stop - xs.start
        streaks = brushed(h, w, self.rng, amp=amp)
        low = brushed(h, w, self.rng, window=160, amp=2.5)
        col = np.asarray(base, np.float32)[None, None, :] + (streaks + low)[..., None]
        self.diffuse[ys, xs] = col
        self.spec[ys, xs] = spec + streaks * 0.01
        self.height[ys, xs] = streaks * 0.003
        self.metal[ys, xs] = 1.0

    def paint_pcb(self, rect, with_traces=True):
        ys, xs = region_slices(rect)
        h, w = ys.stop - ys.start, xs.stop - xs.start
        noise = self.rng.standard_normal((h, w)).astype(np.float32) * 2.5
        weave = (np.sin(np.arange(w) * 1.9)[None, :] * np.sin(np.arange(h) * 1.9)[:, None]) * 2.0
        col = np.asarray(PCB_GREEN, np.float32)[None, None, :] + (noise + weave)[..., None]
        self.diffuse[ys, xs] = col
        self.spec[ys, xs] = 0.22
        self.metal[ys, xs] = 0.0
        if with_traces:
            img = Image.new("L", (w, h), 0)
            d = ImageDraw.Draw(img)
            # faint fibre-glass trace pattern: concentric loops + diagonal fan-outs
            for r in range(26, w // 2 - 6, 9):
                d.rectangle([w // 2 - r, h // 2 - r, w // 2 + r, h // 2 + r], outline=255, width=1)
            for i in range(0, w, 11):
                d.line([(i, 0), (i, h)], fill=90, width=1)
            arr = np.asarray(img, np.float32) / 255.0 * 0.35
            self.diffuse[ys, xs] += (np.asarray(PCB_TRACE, np.float32) - np.asarray(PCB_GREEN, np.float32))[None, None, :] * arr[..., None]
            self.height[ys, xs] += arr * 0.08

    def stamp(self, rect, mask, color=None, spec=None, height=None, metal=None, x=0, y=0):
        """Blend a mask (0..1 float array) into a rect at pixel offset (x, y)."""
        rx0, ry0, rx1, ry1 = rect
        hh, ww = mask.shape
        X0, Y0 = int(rx0 + x), int(ry0 + y)
        X1, Y1 = min(X0 + ww, rx1), min(Y0 + hh, ry1)
        if X1 <= X0 or Y1 <= Y0:
            return
        msk = mask[: Y1 - Y0, : X1 - X0]
        if color is not None:
            c = np.asarray(color, np.float32)[None, None, :]
            self.diffuse[Y0:Y1, X0:X1] = self.diffuse[Y0:Y1, X0:X1] * (1 - msk[..., None]) + c * msk[..., None]
        if spec is not None:
            self.spec[Y0:Y1, X0:X1] = self.spec[Y0:Y1, X0:X1] * (1 - msk) + spec * msk
        if metal is not None:
            self.metal[Y0:Y1, X0:X1] = self.metal[Y0:Y1, X0:X1] * (1 - msk) + metal * msk
        if height is not None:
            self.height[Y0:Y1, X0:X1] += height * msk


def draw_text_mask(w, h, lines):
    """lines: list of (text, font, size, cx, cy, anchor)"""
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for text, fpath, size, cx, cy, anchor in lines:
        d.text((cx, cy), text, font=font(fpath, size), fill=255, anchor=anchor)
    return np.asarray(img, np.float32) / 255.0


def paint_ihs_top(atlas: Atlas):
    rect = R_IHS_TOP
    atlas.paint_metal(rect, base=NICKEL, amp=3.5, spec=0.80)
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    # laser etched markings (fictional brand, no real trademarks)
    lines = [
        ("NZ", FONT_BOLD, 58, 60, 62, "mm"),
        ("NAYZEE", FONT_BOLD, 40, 215, 46, "mm"),
        ("CORE", FONT_REG, 30, 215, 84, "mm"),
        ("X9", FONT_BOLD, 150, w // 2, 215, "mm"),
        ("X9-14900K", FONT_MONO, 42, w // 2, 325, "mm"),
        ("SR0NZ  3.20GHZ", FONT_MONO, 30, w // 2, 372, "mm"),
        ("MADE IN SAN ANDREAS", FONT_REG, 24, w // 2, 416, "mm"),
        ("L4F1 5C21 00A7  (c)'26", FONT_MONO, 20, w // 2, 458, "mm"),
    ]
    mask = draw_text_mask(w, h, lines)
    # logo tile: rounded square behind "NZ"
    tile = Image.new("L", (w, h), 0)
    ImageDraw.Draw(tile).rounded_rectangle([20, 22, 100, 102], radius=14, outline=255, width=5)
    mask = np.maximum(mask, np.asarray(tile, np.float32) / 255.0)
    # tiny data-matrix style block bottom left
    dm = Image.new("L", (w, h), 0)
    dd = ImageDraw.Draw(dm)
    rng = np.random.default_rng(7)
    for i in range(10):
        for j in range(10):
            if rng.random() < 0.5 or i == 0 or j == 0:
                dd.rectangle([24 + i * 6, 408 + j * 6, 24 + i * 6 + 5, 408 + j * 6 + 5], fill=255)
    mask = np.maximum(mask, np.asarray(dm, np.float32) / 255.0)
    soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0
    atlas.stamp(rect, soft, color=NICKEL_DARK, spec=0.55, height=-0.9)


def paint_substrate_top(atlas: Atlas):
    rect = R_SUB_TOP
    atlas.paint_pcb(rect, with_traces=True)
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    half = SUB_W / 2
    # gold pads under the capacitors + silkscreen outlines
    pads = Image.new("L", (w, h), 0)
    silk = Image.new("L", (w, h), 0)
    dp, ds = ImageDraw.Draw(pads), ImageDraw.Draw(silk)
    for (xa, xb, ya, yb) in cap_footprints():
        px0, py0 = metres_to_px((0, 0, w, h), xa, yb, half)
        px1, py1 = metres_to_px((0, 0, w, h), xb, ya, half)
        dp.rectangle([px0 - 3, py0 - 2, px1 + 3, py1 + 2], fill=255)
        ds.rectangle([px0 - 7, py0 - 6, px1 + 7, py1 + 6], outline=255, width=1)
    # pin-1 marker: gold triangle in the -X/-Y corner, next to the chamfer
    tri = [(14, h - 14), (46, h - 14), (14, h - 46)]
    dp.polygon(tri, fill=255)
    # silkscreen text + fiducials
    ds.text((w // 2, 20), "NZ-PCB  REV C", font=font(FONT_MONO, 16), fill=255, anchor="mm")
    ds.text((w // 2, h - 20), "nz_prop_cpu_chip", font=font(FONT_MONO, 14), fill=255, anchor="mm")
    for (fx, fy) in [(22, 22), (w - 22, 22), (w - 22, h - 22)]:
        ds.ellipse([fx - 5, fy - 5, fx + 5, fy + 5], outline=255, width=2)
    atlas.stamp(rect, np.asarray(pads, np.float32) / 255.0, color=GOLD, spec=0.85, metal=1.0, height=0.25)
    atlas.stamp(rect, np.asarray(silk, np.float32) / 255.0, color=SILK_WHITE, spec=0.3)


def paint_substrate_bottom(atlas: Atlas):
    rect = R_SUB_BOT
    atlas.paint_pcb(rect, with_traces=False)
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    pads = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(pads)
    n = 22                      # pad grid
    pitch = (w - 40) / n
    r = pitch * 0.30
    cx0 = 20 + pitch / 2
    for i in range(n):
        for j in range(n):
            # leave the centre free for the decoupling caps and skip the cut corners
            if 8 <= i <= 13 and 8 <= j <= 13:
                continue
            if (i < 2 and j < 2) or (i < 2 and j >= n - 2) or (i >= n - 2 and j < 2) or (i >= n - 2 and j >= n - 2):
                continue
            cx, cy = cx0 + i * pitch, cx0 + j * pitch
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    pm = np.asarray(pads, np.float32) / 255.0
    dome = np.asarray(Image.fromarray((pm * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), np.float32) / 255.0
    atlas.stamp(rect, pm, color=GOLD, spec=0.9, metal=1.0)
    atlas.stamp(rect, dome, height=0.6)
    # centre cluster of tiny caps
    caps = Image.new("L", (w, h), 0)
    ends = Image.new("L", (w, h), 0)
    dc, de = ImageDraw.Draw(caps), ImageDraw.Draw(ends)
    for i in range(4):
        for j in range(5):
            cx, cy = w // 2 - 54 + i * 36, h // 2 - 40 + j * 20
            dc.rectangle([cx - 13, cy - 5, cx + 13, cy + 5], fill=255)
            de.rectangle([cx - 13, cy - 5, cx - 8, cy + 5], fill=255)
            de.rectangle([cx + 8, cy - 5, cx + 13, cy + 5], fill=255)
    atlas.stamp(rect, np.asarray(caps, np.float32) / 255.0, color=CAP_TAN, spec=0.35, height=0.35)
    atlas.stamp(rect, np.asarray(ends, np.float32) / 255.0, color=CAP_SILVER, spec=0.7, metal=1.0)


def paint_small_regions(atlas: Atlas):
    atlas.paint_pcb(R_PCB_EDGE, with_traces=False)
    ys, xs = region_slices(R_PCB_EDGE)
    atlas.diffuse[ys, xs] = atlas.diffuse[ys, xs] * 0.8 + np.asarray(PCB_GREEN_DARK, np.float32) * 0.2
    atlas.paint_metal(R_METAL_SIDE, base=(166, 168, 172), amp=3.0, spec=0.75)
    atlas.paint_metal(R_METAL_FLAT, base=(170, 172, 176), amp=3.5, spec=0.78)
    atlas.fill(R_CAP_BODY, CAP_TAN, 0.35, 0.0)
    ys, xs = region_slices(R_CAP_BODY)
    atlas.diffuse[ys, xs] += atlas.rng.standard_normal((ys.stop - ys.start, xs.stop - xs.start, 1)).astype(np.float32) * 3
    atlas.fill(R_CAP_END, CAP_SILVER, 0.75, 1.0)


def height_to_normal(height: np.ndarray, strength: float) -> np.ndarray:
    """DirectX-style tangent space normal map (green = +v = image down)."""
    h = height.astype(np.float32)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx, ny, nz = -dx * strength, -dy * strength, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], axis=-1)
    return n


def downsample(arr: np.ndarray, size: int) -> np.ndarray:
    f = arr.shape[0] // size
    if f <= 1:
        return arr
    if arr.ndim == 3:
        return arr.reshape(size, f, size, f, arr.shape[2]).mean(axis=(1, 3))
    return arr.reshape(size, f, size, f).mean(axis=(1, 3))


def build_textures(atlas: Atlas):
    paint_ihs_top(atlas)
    paint_substrate_top(atlas)
    paint_substrate_bottom(atlas)
    paint_small_regions(atlas)
    fill_gutters([atlas.diffuse, atlas.spec, atlas.metal], atlas.painted_mask())

    diffuse = np.clip(atlas.diffuse, 0, 255).astype(np.uint8)
    n = height_to_normal(atlas.height, strength=2.2)
    n = downsample(n, NRM_SIZE)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    normal_dx = np.clip((n * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    normal_gl = normal_dx.copy()
    normal_gl[..., 1] = 255 - normal_gl[..., 1]
    spec = np.clip(downsample(atlas.spec, SPEC_SIZE) * 255, 0, 255).astype(np.uint8)
    metal = np.clip(downsample(atlas.metal, SPEC_SIZE) * 255, 0, 255).astype(np.uint8)
    return {
        "diffuse": Image.fromarray(diffuse, "RGB"),
        "normal_dx": Image.fromarray(normal_dx, "RGB"),
        "normal_gl": Image.fromarray(normal_gl, "RGB"),
        "spec": Image.fromarray(np.repeat(spec[..., None], 3, axis=-1), "RGB"),
        # glTF metallic-roughness: G = roughness, B = metallic
        "mr": Image.fromarray(np.stack([np.zeros_like(spec), 255 - spec, metal], axis=-1), "RGB"),
    }


# ----------------------------------------------------------------------------
# DDS writer (DXT1 / DXT5 with a full mip chain)
# ----------------------------------------------------------------------------
DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT = 0x1, 0x2, 0x4, 0x1000
DDSD_MIPMAPCOUNT, DDSD_LINEARSIZE = 0x20000, 0x80000
DDPF_FOURCC = 0x4
DDSCAPS_COMPLEX, DDSCAPS_TEXTURE, DDSCAPS_MIPMAP = 0x8, 0x1000, 0x400000


def encode_dxt_level(img: Image.Image, fmt: str) -> bytes:
    """Encode one mip level with Pillow's BC1/BC3 encoder and strip the header."""
    w, h = img.size
    block = 8 if fmt == "DXT1" else 16
    nblocks = ((w + 3) // 4) * ((h + 3) // 4)
    src = img
    if w < 4 or h < 4:
        # pad tiny levels to a whole 4x4 block by edge replication: a decoder reads the
        # real texels from the top-left w x h corner of the block
        arr = np.asarray(img.convert("RGBA"))
        arr = np.pad(arr, ((0, max(4, h) - h), (0, max(4, w) - w), (0, 0)), mode="edge")
        src = Image.fromarray(arr, "RGBA")
    b = io.BytesIO()
    src.save(b, "DDS", pixel_format=fmt)
    data = b.getvalue()[128:]
    return data[: nblocks * block]


def write_dds(path: str, img: Image.Image, fmt: str):
    assert fmt in ("DXT1", "DXT5")
    img = img.convert("RGBA")
    w, h = img.size
    levels = []
    cur = img
    while True:
        levels.append(encode_dxt_level(cur, fmt))
        if cur.size == (1, 1):
            break
        nw, nh = max(1, cur.size[0] // 2), max(1, cur.size[1] // 2)
        cur = img.resize((nw, nh), Image.LANCZOS)
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT | DDSD_LINEARSIZE
    header = struct.pack("<4sIIIIIII", b"DDS ", 124, flags, h, w, len(levels[0]), 0, len(levels))
    header += b"\x00" * 44  # reserved1[11]
    header += struct.pack("<II4sIIIII", 32, DDPF_FOURCC, fmt.encode("ascii"), 0, 0, 0, 0, 0)
    header += struct.pack("<IIIII", DDSCAPS_COMPLEX | DDSCAPS_TEXTURE | DDSCAPS_MIPMAP, 0, 0, 0, 0)
    assert len(header) == 128
    with open(path, "wb") as f:
        f.write(header)
        for lv in levels:
            f.write(lv)
    return len(levels)


# ----------------------------------------------------------------------------
# CodeWalker XML
# ----------------------------------------------------------------------------
def vec_attr(v):
    return f'x="{f6(v[0])}" y="{f6(v[1])}" z="{f6(v[2])}"'


def shader_xml(tex_d, tex_n, tex_s):
    # parameter order follows the game's normal_spec definition (Sollumz Shaders.xml)
    return f"""    <Shaders>
      <Item>
        <Name>normal_spec</Name>
        <FileName>normal_spec.sps</FileName>
        <RenderBucket value="0" />
        <Parameters>
          <Item name="DiffuseSampler" type="Texture">
            <Name>{tex_d}</Name>
          </Item>
          <Item name="BumpSampler" type="Texture">
            <Name>{tex_n}</Name>
          </Item>
          <Item name="SpecSampler" type="Texture">
            <Name>{tex_s}</Name>
          </Item>
          <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
          <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
          <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
          <Item name="bumpiness" type="Vector" x="1" y="0" z="0" w="0" />
          <Item name="specMapIntMask" type="Vector" x="1" y="0" z="0" w="0" />
          <Item name="specularIntensityMult" type="Vector" x="1.1" y="0" z="0" w="0" />
          <Item name="specularFalloffMult" type="Vector" x="110" y="0" z="0" w="0" />
          <Item name="specularFresnel" type="Vector" x="0.85" y="0" z="0" w="0" />
        </Parameters>
      </Item>
    </Shaders>"""


def texture_item_xml(name, usage, w, h, mips, fmt):
    return f"""      <Item>
        <Name>{name}</Name>
        <Unk32 value="0" />
        <Usage>{usage}</Usage>
        <UsageFlags>UNK24</UsageFlags>
        <ExtraFlags value="0" />
        <Width value="{w}" />
        <Height value="{h}" />
        <MipLevels value="{mips}" />
        <Format>{fmt}</Format>
        <FileName>{name}.dds</FileName>
      </Item>"""


def bound_fields_xml(indent, bmin, bmax, margin, volume, inertia, material_index, unk_type=1):
    c = (bmin + bmax) / 2
    radius = float(np.linalg.norm(bmax - c))
    p = " " * indent
    return "\n".join([
        f'{p}<BoxMin {vec_attr(bmin)} />',
        f'{p}<BoxMax {vec_attr(bmax)} />',
        f'{p}<BoxCenter {vec_attr(c)} />',
        f'{p}<SphereCenter {vec_attr(c)} />',
        f'{p}<SphereRadius value="{f6(radius)}" />',
        f'{p}<Margin value="{f6(margin)}" />',
        f'{p}<Volume value="{volume:.9f}" />',
        f'{p}<Inertia {vec_attr(inertia)} />',
        f'{p}<MaterialIndex value="{material_index}" />',
        f'{p}<MaterialColourIndex value="0" />',
        f'{p}<ProceduralID value="0" />',
        f'{p}<RoomID value="0" />',
        f'{p}<PedDensity value="0" />',
        f'{p}<UnkFlags value="0" />',
        f'{p}<PolyFlags value="0" />',
        f'{p}<UnkType value="{unk_type}" />',
    ])


def bounds_xml(col_min, col_max):
    ext = col_max - col_min
    volume = float(ext[0] * ext[1] * ext[2])
    # inertia of a solid box with unit density (what Sollumz/R* store)
    inertia = v3((ext[1] ** 2 + ext[2] ** 2) / 12, (ext[0] ** 2 + ext[2] ** 2) / 12, (ext[0] ** 2 + ext[1] ** 2) / 12)
    margin = min(0.04, float(ext.min()) / 8)
    identity = "\n".join("        1 0 0 0" if i == 0 else ("        0 1 0 0" if i == 1 else ("        0 0 1 0" if i == 2 else "        0 0 0 1")) for i in range(4))
    return f"""  <Bounds type="Composite">
{bound_fields_xml(4, col_min, col_max, 0.0, volume, inertia, 0)}
    <Children>
      <Item type="Box">
{bound_fields_xml(8, col_min, col_max, margin, volume, inertia, COLLISION_MATERIAL_INDEX)}
        <CompositeTransform>
{identity}
        </CompositeTransform>
        <CompositeFlags1>{COMPOSITE_FLAGS1}</CompositeFlags1>
        <CompositeFlags2>{COMPOSITE_FLAGS2}</CompositeFlags2>
      </Item>
    </Children>
  </Bounds>"""


def ydr_xml(mesh: Mesh, tex_info, col_min, col_max, lod_dist=9998.0):
    bmin, bmax = mesh.bbox()
    center = (bmin + bmax) / 2
    radius = float(np.linalg.norm(bmax - center))
    rows = []
    for p, n, uv, t in zip(mesh.positions, mesh.normals, mesh.uvs, mesh.tangents):
        rows.append("          " + "   ".join([
            f"{f6(p[0])} {f6(p[1])} {f6(p[2])}",
            f"{f6(n[0])} {f6(n[1])} {f6(n[2])}",
            "255 255 255 255",
            f"{f6(uv[0])} {f6(uv[1])}",
            f"{f6(t[0])} {f6(t[1])} {f6(t[2])} {f6(t[3])}",
        ]))
    idx_lines = []
    for i in range(0, len(mesh.indices), 24):
        idx_lines.append("          " + " ".join(str(k) for k in mesh.indices[i:i + 24]))
    tex_items = "\n".join(texture_item_xml(*ti) for ti in tex_info)
    names = [ti[0] for ti in tex_info]
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
  <Name>{PROP_NAME}</Name>
  <BoundingSphereCenter {vec_attr(center)} />
  <BoundingSphereRadius value="{f6(radius)}" />
  <BoundingBoxMin {vec_attr(bmin)} />
  <BoundingBoxMax {vec_attr(bmax)} />
  <LodDistHigh value="{lod_dist}" />
  <LodDistMed value="{lod_dist}" />
  <LodDistLow value="{lod_dist}" />
  <LodDistVlow value="{lod_dist}" />
  <FlagsHigh value="1" />
  <FlagsMed value="0" />
  <FlagsLow value="0" />
  <FlagsVlow value="0" />
  <ShaderGroup>
    <TextureDictionary>
{tex_items}
    </TextureDictionary>
{shader_xml(*names)}
  </ShaderGroup>
  <DrawableModelsHigh>
    <Item>
      <RenderMask value="255" />
      <Flags value="0" />
      <HasSkin value="0" />
      <BoneIndex value="0" />
      <Unknown1 value="0" />
      <Geometries>
        <Item>
          <ShaderIndex value="0" />
          <BoundingBoxMin {vec_attr(bmin)} w="0" />
          <BoundingBoxMax {vec_attr(bmax)} w="0" />
          <VertexBuffer>
            <Flags value="0" />
            <Layout type="GTAV1">
              <Position />
              <Normal />
              <Colour0 />
              <TexCoord0 />
              <Tangent />
            </Layout>
            <Data>
{chr(10).join(rows)}
            </Data>
          </VertexBuffer>
          <IndexBuffer>
            <Data>
{chr(10).join(idx_lines)}
            </Data>
          </IndexBuffer>
        </Item>
      </Geometries>
    </Item>
  </DrawableModelsHigh>
{bounds_xml(col_min, col_max)}
</Drawable>
"""


def ytyp_xml(bmin, bmax, flags=0, lod_dist=50.0, hd_tex_dist=15.0):
    center = (bmin + bmax) / 2
    radius = float(np.linalg.norm(bmax - center))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<CMapTypes>
  <extensions />
  <archetypes>
    <Item type="CBaseArchetypeDef">
      <lodDist value="{lod_dist}" />
      <flags value="{flags}" />
      <specialAttribute value="0" />
      <bbMin {vec_attr(bmin)} />
      <bbMax {vec_attr(bmax)} />
      <bsCentre {vec_attr(center)} />
      <bsRadius value="{f6(radius)}" />
      <hdTextureDist value="{hd_tex_dist}" />
      <name>{PROP_NAME}</name>
      <textureDictionary />
      <clipDictionary />
      <drawableDictionary />
      <physicsDictionary />
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{PROP_NAME}</assetName>
      <extensions />
    </Item>
  </archetypes>
  <name>{YTYP_NAME}</name>
  <dependencies />
  <compositeEntityTypes />
</CMapTypes>
"""


# ----------------------------------------------------------------------------
# preview assets: mesh.json (Y-up) and a binary glTF
# ----------------------------------------------------------------------------
def to_yup(v):
    return (float(v[0]), float(v[2]), float(-v[1]))


def write_mesh_json(path, mesh: Mesh):
    data = {
        "positions": [c for p in mesh.positions for c in to_yup(p)],
        "normals": [c for n in mesh.normals for c in to_yup(n)],
        "tangents": [c for t in mesh.tangents for c in (*to_yup(t[:3]), float(t[3]))],
        "uvs": [c for uv in mesh.uvs for c in uv],
        "indices": list(mesh.indices),
    }
    with open(path, "w") as f:
        json.dump(data, f)


def write_glb(path, mesh: Mesh, textures: dict):
    def png_bytes(img):
        b = io.BytesIO()
        img.save(b, "PNG", optimize=True)
        return b.getvalue()

    pos = np.array([to_yup(p) for p in mesh.positions], np.float32)
    nrm = np.array([to_yup(n) for n in mesh.normals], np.float32)
    tan = np.array([(*to_yup(t[:3]), t[3]) for t in mesh.tangents], np.float32)
    uv = np.array(mesh.uvs, np.float32)
    idx = np.array(mesh.indices, np.uint16)
    blobs = [pos.tobytes(), nrm.tobytes(), tan.tobytes(), uv.tobytes(), idx.tobytes(),
             png_bytes(textures["diffuse"]), png_bytes(textures["normal_gl"]), png_bytes(textures["mr"])]
    views, offset, bin_data = [], 0, b""
    for i, b in enumerate(blobs):
        pad = (-len(b)) % 4
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(b)})
        if i < 4:
            views[-1]["target"] = 34962
        elif i == 4:
            views[-1]["target"] = 34963
        bin_data += b + b"\x00" * pad
        offset += len(b) + pad
    gltf = {
        "asset": {"version": "2.0", "generator": "nz_cpuchip builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": PROP_NAME}],
        "meshes": [{"name": PROP_NAME, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TANGENT": 2, "TEXCOORD_0": 3},
            "indices": 4, "material": 0}]}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(tan), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 4, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_data)}],
        "images": [{"bufferView": 5, "mimeType": "image/png"},
                   {"bufferView": 6, "mimeType": "image/png"},
                   {"bufferView": 7, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}, {"source": 2, "sampler": 0}],
        "materials": [{
            "name": "nz_cpu_chip",
            "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 2},
                                     "metallicFactor": 1.0, "roughnessFactor": 1.0},
            "normalTexture": {"index": 1},
        }],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942) + bin_data)


# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="out", help="output folder")
    ap.add_argument("--archetype-flags", type=int, default=0, help="ytyp archetype flags (0 = dynamic prop, 32 = static)")
    ap.add_argument("--lod-dist", type=float, default=50.0, help="archetype lodDist (metres)")
    args = ap.parse_args()

    out = args.out
    src = os.path.join(out, "source")
    dds_dir = os.path.join(src, PROP_NAME)          # CodeWalker looks for DDS files in <xmlname-without-ext>/
    prev = os.path.join(out, "preview")
    for d in (src, dds_dir, prev):
        os.makedirs(d, exist_ok=True)

    mesh = build_mesh()
    bmin, bmax = mesh.bbox()
    print(f"mesh: {len(mesh.positions)} verts, {len(mesh.indices) // 3} tris, bbox {bmin.round(4)} .. {bmax.round(4)}")

    atlas = Atlas(TEX_SIZE)
    textures = build_textures(atlas)

    tex_d, tex_n, tex_s = f"{PROP_NAME}_d", f"{PROP_NAME}_n", f"{PROP_NAME}_s"
    md = write_dds(os.path.join(dds_dir, tex_d + ".dds"), textures["diffuse"], "DXT1")
    mn = write_dds(os.path.join(dds_dir, tex_n + ".dds"), textures["normal_dx"], "DXT5")
    ms = write_dds(os.path.join(dds_dir, tex_s + ".dds"), textures["spec"], "DXT1")
    tex_info = [
        (tex_d, "DIFFUSE", TEX_SIZE, TEX_SIZE, md, "D3DFMT_DXT1"),
        (tex_n, "NORMAL", NRM_SIZE, NRM_SIZE, mn, "D3DFMT_DXT5"),
        (tex_s, "SPECULAR", SPEC_SIZE, SPEC_SIZE, ms, "D3DFMT_DXT1"),
    ]

    # collision: one box covering substrate + lid
    col_min = v3(-SUB_W / 2, -SUB_W / 2, 0.0)
    col_max = v3(SUB_W / 2, SUB_W / 2, SUB_T + IHS_FLANGE_T + IHS_CORE_H)

    with open(os.path.join(src, PROP_NAME + ".ydr.xml"), "w", encoding="utf-8") as f:
        f.write(ydr_xml(mesh, tex_info, col_min, col_max))
    with open(os.path.join(src, PROP_NAME + ".ytyp.xml"), "w", encoding="utf-8") as f:
        f.write(ytyp_xml(bmin, bmax, flags=args.archetype_flags, lod_dist=args.lod_dist))

    # preview + editing assets
    textures["diffuse"].save(os.path.join(prev, tex_d + ".png"))
    textures["normal_dx"].save(os.path.join(prev, tex_n + ".png"))
    textures["spec"].save(os.path.join(prev, tex_s + ".png"))
    textures["mr"].save(os.path.join(prev, PROP_NAME + "_mr.png"))
    write_mesh_json(os.path.join(prev, "mesh.json"), mesh)
    write_glb(os.path.join(out, PROP_NAME + ".glb"), mesh, textures)
    print(f"wrote {src}/{PROP_NAME}.ydr.xml, {PROP_NAME}.ytyp.xml, DDS x3 (mips {md}/{mn}/{ms}), preview assets and {PROP_NAME}.glb")


if __name__ == "__main__":
    main()
