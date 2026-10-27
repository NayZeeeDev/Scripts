"""
nzprops.prop - prop registry, the Builder API used by prop definitions, and the per-prop pipeline
(pack -> bake -> tangents -> DDS -> CodeWalker XML -> glTF -> manifest).

Defining a prop (tools/props/props/*.py):

    from nzprops import *

    @prop("nzr_example", atlas=512, lod=60, doc={...})
    def example(b: Builder):
        shell = b.mat("shell", color=(70, 74, 78), spec=0.3, gloss=0.45, bump="stipple")
        b.add(box((0.2, 0.1, 0.05), shell, r=0.006, center=(0, 0, 0.025)))
        dc = DecalCanvas(0.08, 0.03); dc.text(0.04, 0.015, "JX-10", 0.006)
        b.decal(dc, center=(0, 0.0501, 0.03), normal=(0, 1, 0))
        b.col_box((-0.1, -0.05, 0), (0.1, 0.05, 0.05), "PLASTIC_HIGH_DENSITY")

Layers (picked from each chart's material):
    main   -> normal_spec  (<name>_d DXT1, <name>_n DXT5, <name>_s DXT5 RGB=intensity A=gloss; _n/_s at half size above 1024)
    alpha  -> normal_spec_alpha (<name>_ad DXT5 with alpha, <name>_an, <name>_as)   glass, clear lenses
    glow   -> emissive (<name>_g)                       LEDs / indicator lights
    screen -> emissive with a fixed-UV texture named by b.screen() (nzr_scr on the radios)
    <custom> -> extra normal_spec atlas (<name>_<layer>_d/_n/_s) for big props that need more texels:
               declare it with @prop(..., layers={"sup": 1024}) and give materials layer="sup".

Normal / spec map sizes: full size up to 1024, half size above. @prop(..., maps={"main": {"n": 512, "s": 512}})
overrides them per layer (main / alpha / custom layers) - the GPU-memory lever: every streamed drawable must
stay <= 16 MiB of physical (graphics) pages, which build.py checks (estimated here, exact after conversion).

LOD: every chart is flagged 'hm' (both models, default), 'h' (high model only: fine detail) or 'm' (medium
model only: a cheap stand-in). Builder.add(geo, lod="h") / b.hi_only(geo) set it; @prop(med_drop=0.003)
also drops every chart smaller than 3 mm from the medium model. When anything differs, the drawable gets a
medium model used from lod_high metres out to the archetype lodDist; otherwise one model is used throughout.

Parts: `with b.part("k1", action="digit", value="1", ...):` tags everything added inside (geometry and
decals) with a part id. Decals only print on charts of their own part (the body's decals never bleed onto
a key cap and vice versa). The radio kit (props/radio_kit.py) splits a design into full / body / part models
with this.

Anchors: b.anchor(name=value, ...) stores JSON-able data in the manifest ("anchors") - the layout
generator (gen_layout.py) reads screen / focus / leds / key anchors and jammer interact points from there.

Preview options (tools/props/preview, never shipped): @prop(..., preview={...}) or b.preview_cam(...)
    views   list of view names used on the contact sheet instead of the global ones
            (built-ins: front (3/4), face, front34, left, right, side, back, back34, top, frontlow, iso)
    cams    [{"name", "pos", "target", "fov", "clipZ"?}] extra cameras in GTA prop space
    lights  [{"pos", "intensity", "distance"?, "color"?}] point lights (interiors)
"""
from __future__ import annotations

import contextlib
import json
import os
import time
from dataclasses import dataclass, field
from typing import Callable

import numpy as np
from PIL import Image

from .atlas import chart_px, pack_charts, rasterize
from .bake import AOField, ChartDecal, Decal, bake
from .budget import estimate as mem_estimate
from .cwxml import COL_MATERIALS, ColShape, ShaderGeom, archetype_xml, drawable_xml
from .dds import FORMATS, write_dds
from .fsutil import save_image, write_json, write_text
from .gltf import write_glb
from .mesh import Geo, normalize
from .paint import DecalCanvas, Mat

FLAG_STATIC = 32                 # archetype flag: static (no physics response)


@dataclass
class PropSpec:
    name: str
    fn: Callable
    atlas: int = 512              # main atlas size (px)
    alpha_atlas: int = 256
    glow_atlas: int = 64
    lod: float = 60.0             # archetype lodDist (m)
    hd: float = 15.0              # hdTextureDist
    static: bool = False
    flags: int = 0
    doc: dict = field(default_factory=dict)
    falloff: float = 100.0        # specularFalloffMult of the main shader (spec alpha scales it)
    spec_mult: float = 1.0        # specularIntensityMult
    glow_mult: float = 2.0        # emissiveMultiplier for the glow layer
    layers: dict = field(default_factory=dict)    # extra normal_spec atlases {layer name: size}
    maps: dict = field(default_factory=dict)      # per-layer normal / spec map sizes {layer: {"n": px, "s": px}}
    preview: dict = field(default_factory=dict)   # preview-only cameras / lights / views
    module: str = ""
    lod_high: float = 8.0         # LodDistHigh when the prop has a medium model (high -> medium switch)
    med_drop: float = 0.0         # charts smaller than this (bbox diagonal, m) are left out of the medium model
    export: bool = True           # False: built + rendered (icons, previews) but never streamed / in the ytyp
    budget: int = 0               # triangle budget of the high model (0 = none); exceeding it is a warning
    group: str = ""               # contact-sheet group (the radio kit uses "radio:<key>")


REGISTRY: dict[str, PropSpec] = {}


def prop(name, **kw):
    def deco(fn):
        register(name, fn, **kw)
        return fn
    return deco


def register(name, fn, **kw):
    if name in REGISTRY:
        raise ValueError(f"prop {name} registered twice")
    module = kw.pop("module", None) or getattr(fn, "__module__", "")
    spec = PropSpec(name=name, fn=fn, module=module, **kw)
    for layer, ov in spec.maps.items():
        if layer not in ("main", "alpha") and layer not in spec.layers:
            raise ValueError(f"prop {name}: maps= names layer '{layer}' that has no normal / spec maps")
        for k, v in ov.items():
            if k not in ("n", "s") or int(v) < 4 or int(v) & (int(v) - 1):
                raise ValueError(f"prop {name}: maps['{layer}'] needs 'n' / 's' power-of-two sizes, got {k}={v}")
    REGISTRY[name] = spec
    return spec


# ---------------------------------------------------------------------------------------------
# builder
# ---------------------------------------------------------------------------------------------
class Builder:
    def __init__(self, spec: PropSpec):
        self.spec = spec
        self.name = spec.name
        self.mats: dict[str, Mat] = {}
        self.geo = Geo()
        self.decals: list[Decal] = []
        self.chart_decals: list[ChartDecal] = []
        self.shapes: list[ColShape] = []
        self.screens: dict[str, tuple] = {}    # texture name -> (PIL image, emissive multiplier, size)
        self.notes: dict = {}
        self.anchors: dict = {}                # JSON-able data for the manifest (layout generator input)
        self.parts: dict = {}                  # part id -> metadata given to part()
        self.occluders: list = []              # extra (m,3,3) triangle arrays that only cast ambient occlusion
        self.preview: dict = {}                # runtime additions to spec.preview (views / cams / lights / extra)
        self.warnings: list[str] = []
        self._part = None

    # materials --------------------------------------------------------------------------
    def mat(self, name, **kw):
        if name in self.mats:
            return name
        self.mats[name] = Mat(**kw)
        return name

    def mat_from(self, name, m: Mat):
        self.mats[name] = m
        return name

    # parts / anchors --------------------------------------------------------------------
    @contextlib.contextmanager
    def part(self, pid, **meta):
        """Everything added (geometry, decals, screens) inside the block belongs to part `pid`."""
        if not isinstance(pid, str) or not pid:
            raise ValueError("part id must be a non-empty string")
        prev = self._part
        self._part = pid
        self.parts.setdefault(pid, {}).update(meta)
        try:
            yield self
        finally:
            self._part = prev

    @property
    def current_part(self):
        return self._part

    def anchor(self, **kw):
        """Store named anchors (tuples / numbers / strings / dicts) in the manifest."""
        for k, v in kw.items():
            self.anchors[k] = _jsonable(v)
        return self.anchors

    def preview_cam(self, name, pos, target, fov=40.0, clipZ=None):
        cam = {"name": name, "pos": [float(v) for v in pos], "target": [float(v) for v in target], "fov": float(fov)}
        if clipZ is not None:
            cam["clipZ"] = float(clipZ)
        self.preview.setdefault("cams", []).append(cam)
        return cam

    def closeup(self, name, target, direction=(0.2, 1.0, 0.35), extent=0.1, fov=30.0, fill=0.8):
        """Review camera framing a region: looks at `target` from `direction` (prop space) so that a
        region `extent` metres across fills `fill` of the frame."""
        import math as _m
        d = normalize(np.asarray(direction, np.float64))
        dist = (extent / 2) / (_m.tan(_m.radians(fov / 2)) * fill)
        return self.preview_cam(name, np.asarray(target, np.float64) + d * dist, target, fov)

    def warn(self, msg):
        self.warnings.append(msg)

    # geometry ---------------------------------------------------------------------------
    def add(self, *geos, lod=None):
        """Add geometry. Charts take the current part() id; lod='h' / 'm' / 'hm' sets the LOD flag."""
        for g in geos:
            n0 = len(self.geo.charts)
            self.geo += g
            for c in self.geo.charts[n0:]:
                if self._part is not None and c.part is None:
                    c.part = self._part
                if lod is not None:
                    c.lod = lod
        return geos[0] if len(geos) == 1 else geos

    def hi_only(self, *geos):
        """Add fine detail that the medium (distance) model leaves out."""
        return self.add(*geos, lod="h")

    def screen(self, geo: Geo, texname="nzr_scr", image: Image.Image | None = None, mult=1.0, size=(512, 256)):
        """Add a screen quad (geometry with fixed 0..1 UVs, see mesh.quad(..., fixed_uv=True))."""
        key = "screen:" + texname
        for c in geo.charts:
            if c.fixed_uv is None:
                raise ValueError("screen geometry needs fixed UVs (quad(..., fixed_uv=True))")
            c.mat = key
        if image is None:
            image = Image.new("RGB", size, (8, 10, 12))
        self.screens[texname] = (image.convert("RGB").resize(size, Image.LANCZOS), mult, tuple(size))
        self.add(geo)
        return geo

    # decals -----------------------------------------------------------------------------
    def decal(self, canvas: DecalCanvas, center, normal, up=(0, 0, 1), depth=0.01, mats=None, min_dot=0.25, part=None):
        """Project a canvas. It prints on charts of the current part() (or `part`; "*" = everything)."""
        pid = part if part is not None else (self._part or "")
        self.decals.append(Decal(canvas, tuple(center), tuple(normal), tuple(up), depth, None if mats is None else tuple(mats),
                                 min_dot, pid))

    def chart_decal(self, canvas: DecalCanvas, tag, u0=0.0, v0=0.0, rot=0, repeat_v=0.0, mats=None, mirror=False, part=None):
        """Place a canvas in chart space (metres along the surface) of charts whose tag starts with
        `tag` - e.g. prints that follow a swept strap. rot 90 runs the canvas x along the path."""
        pid = part if part is not None else (self._part or "")
        self.chart_decals.append(ChartDecal(canvas, tag, u0, v0, rot, repeat_v, None if mats is None else tuple(mats), mirror, pid))

    # collision --------------------------------------------------------------------------
    def col_box(self, mn, mx, material="PLASTIC_HIGH_DENSITY"):
        mn, mx = np.asarray(mn, float), np.asarray(mx, float)
        lo, hi = np.minimum(mn, mx), np.maximum(mn, mx)
        if material not in COL_MATERIALS:
            raise ValueError(f"unknown collision material {material}")
        self.shapes.append(ColShape("box", (lo + hi) / 2, np.maximum(hi - lo, 0.002), material=material))

    def col_cyl(self, center, radius, length, axis="z", material="METAL_SOLID_SMALL"):
        if material not in COL_MATERIALS:
            raise ValueError(f"unknown collision material {material}")
        self.shapes.append(ColShape("cylinder", np.asarray(center, float), np.array([max(radius, 0.002), max(length, 0.004), 0.0]), axis, material))


def _jsonable(v):
    if isinstance(v, np.ndarray):
        return [_jsonable(x) for x in v.tolist()]
    if isinstance(v, (list, tuple)):
        return [_jsonable(x) for x in v]
    if isinstance(v, dict):
        return {str(k): _jsonable(x) for k, x in v.items()}
    if isinstance(v, (np.floating, float)):
        return round(float(v), 6)
    if isinstance(v, (np.integer,)):
        return int(v)
    return v


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------
def compute_tangents(pos, nrm, uv, tri):
    """Per-vertex tangents (x, y, z, w) with w chosen so cross(T, N) * w = dP/dv (GTA convention)."""
    t_acc = np.zeros_like(pos)
    b_acc = np.zeros_like(pos)
    p0, p1, p2 = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    w0, w1, w2 = uv[tri[:, 0]], uv[tri[:, 1]], uv[tri[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = w1 - w0, w2 - w0
    det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    ok = np.abs(det) > 1e-14
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    T = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * inv[:, None]
    B = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * inv[:, None]
    for k in range(3):
        np.add.at(t_acc, tri[:, k], T)
        np.add.at(b_acc, tri[:, k], B)
    t = t_acc - nrm * np.einsum("ij,ij->i", nrm, t_acc)[:, None]
    bad = np.linalg.norm(t, axis=1) < 1e-12
    if bad.any():
        a = np.where(np.abs(nrm[bad, 0:1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]]))
        t[bad] = np.cross(nrm[bad], a)
    t = normalize(t)
    w = np.where(np.einsum("ij,ij->i", np.cross(t, nrm), b_acc) >= 0, 1.0, -1.0)
    return np.concatenate([t, w[:, None]], axis=1)


BUILTIN_LAYERS = ("main", "alpha", "glow")


def _layer_of(b: Builder, matname: str):
    if matname.startswith("screen:"):
        return "screen"
    if matname not in b.mats:
        raise KeyError(f"{b.name}: material '{matname}' used but not defined")
    layer = b.mats[matname].layer
    if layer not in BUILTIN_LAYERS and layer not in b.spec.layers:
        raise KeyError(f"{b.name}: material '{matname}' uses layer '{layer}' that is not declared in layers=")
    return layer


def _resolve_lods(b: Builder):
    """Final LOD flag per chart ('hm' / 'h' / 'm'), applying @prop(med_drop=...). Returns has_medium."""
    md = float(b.spec.med_drop or 0.0)
    for c in b.geo.charts:
        if c.lod not in ("hm", "h", "m"):
            raise ValueError(f"{b.name}: chart '{c.tag}' has an invalid lod flag {c.lod!r}")
        if md > 0 and c.lod == "hm" and not c.mat.startswith("screen:"):
            if float(np.linalg.norm(c.pos.max(axis=0) - c.pos.min(axis=0))) < md:
                c.lod = "h"
    return any(c.lod != "hm" for c in b.geo.charts)


def _payload(path):
    try:
        return max(0, os.path.getsize(path) - 128)
    except OSError:
        return 0


# ---------------------------------------------------------------------------------------------
# pipeline
# ---------------------------------------------------------------------------------------------
def build_prop(spec: PropSpec, out_root: str, quick=False):
    """Build one prop into out_root/<name>/ (every file written atomically, manifest.json last).
    Returns the manifest dict."""
    b = Builder(spec)
    spec.fn(b)
    name = spec.name
    if not b.geo.charts:
        raise RuntimeError(f"{name}: no geometry")
    if not b.shapes:
        raise RuntimeError(f"{name}: no collision")
    pdir = os.path.join(out_root, name)
    src = os.path.join(pdir, "source")
    dds_dir = os.path.join(src, name)
    prev = os.path.join(pdir, "preview")
    for d in (src, dds_dir, prev):
        os.makedirs(d, exist_ok=True)

    has_med = _resolve_lods(b)
    charts = b.geo.charts
    layers: dict[str, list] = {}
    for c in charts:
        layers.setdefault(_layer_of(b, c.mat), []).append(c)

    all_tris = np.concatenate([c.pos[c.tri] for c in charts])
    occ = [np.asarray(t, np.float64).reshape(-1, 3, 3) for t in b.occluders if len(t)]
    ao = None if quick else AOField(np.concatenate([all_tris] + occ) if occ else all_tris)

    geoms: list[ShaderGeom] = []
    textures = []
    glb_groups, glb_med = [], []
    tex_summary = []
    tex_files = set()
    sizes = {"main": spec.atlas, "alpha": spec.alpha_atlas, "glow": spec.glow_atlas}
    sizes.update({k: int(v) for k, v in spec.layers.items()})
    order = ["main"] + sorted(spec.layers) + ["alpha", "glow"]

    def lod_idx(lc, T_v):
        """(high triangles, medium triangles or None) of a layer from its charts' LOD flags."""
        flags = np.concatenate([np.full(len(c.tri), c.lod, dtype=object) for c in lc])
        hi = T_v[np.isin(flags, ("hm", "h"))]
        med = T_v[np.isin(flags, ("hm", "m"))] if has_med else None
        return hi, med

    for layer in order:
        lc = layers.get(layer)
        if not lc:
            continue
        S = sizes[layer]
        dens, places = pack_charts(lc, S, S, pad=4 if S >= 256 else 2)
        vpos, vnrm, vuvm, vuv, tri_v, tri_mat, tri_chart, tags, cdens, cparts = [], [], [], [], [], [], [], [], [], []
        base = 0
        tri_px = []
        for ci, (c, pl) in enumerate(zip(lc, places)):
            px = chart_px(c, pl)
            vpos.append(c.pos)
            vnrm.append(c.nrm)
            vuvm.append(c.uvm)
            vuv.append(px / np.array([S, S]))
            tri_v.append(c.tri + base)
            tri_px.append(px[c.tri])
            tri_mat.extend([c.mat] * len(c.tri))
            tri_chart.extend([ci] * len(c.tri))
            tags.append(c.tag)
            cdens.append(pl.dens)
            cparts.append(c.part)
            base += len(c.pos)
        V_pos = np.concatenate(vpos)
        V_nrm = np.concatenate(vnrm)
        V_uvm = np.concatenate(vuvm)
        V_uv = np.concatenate(vuv)
        T_v = np.concatenate(tri_v)
        tid, bary = rasterize(np.concatenate(tri_px), S, S)
        used_mats = {k: v for k, v in b.mats.items() if v.layer == layer}
        imgs = bake(S, S, tid, bary, T_v, V_pos, V_nrm, V_uvm, tri_mat, np.asarray(tri_chart), tags, cdens,
                    used_mats, b.decals, b.chart_decals, ao, alpha_layer=(layer == "alpha"), glow_layer=(layer == "glow"),
                    chart_parts=cparts)
        tan = compute_tangents(V_pos, V_nrm, V_uv, T_v)
        idx_hi, idx_med = lod_idx(lc, T_v)
        prefix = {"main": "", "alpha": "a", "glow": "g"}.get(layer, layer + "_")
        if layer == "glow":
            tn = f"{name}_g"
            mips = write_dds(os.path.join(dds_dir, tn + ".dds"), imgs["diffuse"], "DXT1")
            tex_files.add(tn + ".dds")
            textures.append((tn, "DIFFUSE", S, S, mips, FORMATS["DXT1"]))
            geoms.append(ShaderGeom("emissive", {"DiffuseSampler": tn}, {"emissiveMultiplier": (spec.glow_mult,)},
                                    V_pos, V_nrm, V_uv, None, idx_hi, idx_med=idx_med))
            save_image(imgs["diffuse"], os.path.join(prev, tn + ".png"))
            mat = {"kind": "emissive", "name": "glow", "emissive": imgs["diffuse"]}
            glb_groups.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": None, "idx": idx_hi, "material": mat})
            if has_med:
                glb_med.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": None, "idx": idx_med, "material": mat})
            tex_summary.append({"name": tn, "size": S, "density": round(dens, 1)})
            continue
        tn_d, tn_n, tn_s = f"{name}_{prefix}d", f"{name}_{prefix}n", f"{name}_{prefix}s"
        dfmt = "DXT5" if layer == "alpha" else "DXT1"
        md = write_dds(os.path.join(dds_dir, tn_d + ".dds"), imgs["diffuse"], dfmt)
        NS = S if S <= 1024 else S // 2      # sharp normal / spec detail up to 1024, half size above
        ov = spec.maps.get(layer, {})
        NN, NSP = int(ov.get("n", NS)), int(ov.get("s", NS))    # per-layer override (GPU memory budget)
        nimg = imgs["normal_dx"].resize((NN, NN), Image.LANCZOS) if NN != S else imgs["normal_dx"]
        simg = imgs["spec"].resize((NSP, NSP), Image.LANCZOS) if NSP != S else imgs["spec"]
        mn = write_dds(os.path.join(dds_dir, tn_n + ".dds"), nimg, "DXT5", normal_map=True)
        ms = write_dds(os.path.join(dds_dir, tn_s + ".dds"), simg, "DXT5")
        tex_files.update({tn_d + ".dds", tn_n + ".dds", tn_s + ".dds"})
        textures += [(tn_d, "DIFFUSE", S, S, md, FORMATS[dfmt]), (tn_n, "NORMAL", NN, NN, mn, FORMATS["DXT5"]),
                     (tn_s, "SPECULAR", NSP, NSP, ms, FORMATS["DXT5"])]
        shader = "normal_spec_alpha" if layer == "alpha" else "normal_spec"
        geoms.append(ShaderGeom(shader, {"DiffuseSampler": tn_d, "BumpSampler": tn_n, "SpecSampler": tn_s},
                                {"specularFalloffMult": (spec.falloff,), "specularIntensityMult": (spec.spec_mult,),
                                 "specularFresnel": (0.9,)},
                                V_pos, V_nrm, V_uv, tan, idx_hi, idx_med=idx_med))
        for k, img in (("diffuse", imgs["diffuse"]), ("normal_dx", imgs["normal_dx"]), ("spec", imgs["spec"]), ("mr", imgs["mr"]), ("ao", imgs["ao"])):
            save_image(img, os.path.join(prev, f"{name}_{prefix}{k}.png"))
        mat = {"kind": "alpha" if layer == "alpha" else "pbr", "name": layer,
               "base": imgs["diffuse"], "normal": imgs["normal_gl"], "mr": imgs["mr"]}
        glb_groups.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": tan, "idx": idx_hi, "material": mat})
        if has_med:
            glb_med.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": tan, "idx": idx_med, "material": mat})
        tex_summary.append({"name": tn_d, "size": S, "density": round(dens, 1), "coverage": round(imgs["coverage"], 3),
                            "maps": [NN, NSP]})

    # screens (fixed UVs, emissive, in every LOD)
    for texname, (img, mult, size) in b.screens.items():
        sc = [c for c in layers.get("screen", []) if c.mat == "screen:" + texname]
        if not sc:
            continue
        pos = np.concatenate([c.pos for c in sc])
        nrm = np.concatenate([c.nrm for c in sc])
        uv = np.concatenate([c.fixed_uv for c in sc])
        idx = []
        base = 0
        for c in sc:
            idx.append(c.tri + base)
            base += len(c.pos)
        idx = np.concatenate(idx)
        mips = write_dds(os.path.join(dds_dir, texname + ".dds"), img, "DXT1")
        tex_files.add(texname + ".dds")
        textures.append((texname, "DIFFUSE", size[0], size[1], mips, FORMATS["DXT1"]))
        geoms.append(ShaderGeom("emissive", {"DiffuseSampler": texname}, {"emissiveMultiplier": (mult,)}, pos, nrm, uv, None, idx,
                                idx_med=idx if has_med else None))
        save_image(img, os.path.join(prev, texname + ".png"))
        mat = {"kind": "emissive", "name": texname, "emissive": img}
        glb_groups.append({"pos": pos, "nrm": nrm, "uv": uv, "tan": None, "idx": idx, "material": mat})
        if has_med:
            glb_med.append({"pos": pos, "nrm": nrm, "uv": uv, "tan": None, "idx": idx, "material": mat})
        tex_summary.append({"name": texname, "size": list(size), "screen": True})

    # textures of an earlier version that this one no longer has
    for f in os.listdir(dds_dir):
        if f.endswith(".dds") and f not in tex_files:
            with contextlib.suppress(OSError):
                os.remove(os.path.join(dds_dir, f))

    xml, (bmin, bmax, center, radius), (cmin, cmax), stats = drawable_xml(name, geoms, textures, b.shapes, lod_high=spec.lod_high)
    write_text(os.path.join(src, name + ".ydr.xml"), xml)
    amin = np.minimum(bmin, cmin)
    amax = np.maximum(bmax, cmax)
    acen = (amin + amax) / 2
    arad = float(np.linalg.norm(amax - acen))
    flags = spec.flags | (FLAG_STATIC if spec.static else 0)
    arch = archetype_xml(name, amin, amax, acen, arad, spec.lod, flags, spec.hd)
    write_glb(os.path.join(pdir, name + ".glb"), name, glb_groups)
    if has_med:
        write_glb(os.path.join(pdir, name + "_med.glb"), name, glb_med)
    elif os.path.exists(os.path.join(pdir, name + "_med.glb")):
        os.remove(os.path.join(pdir, name + "_med.glb"))
    mem = mem_estimate([_payload(os.path.join(dds_dir, t[0] + ".dds")) for t in textures], stats["lod_geoms"], len(geoms),
                       len(b.shapes))
    if spec.budget and stats["tris"] > spec.budget:
        b.warn(f"{stats['tris']} tris is over the {spec.budget} budget")
    preview = {k: (list(v) if isinstance(v, list) else v) for k, v in spec.preview.items()}
    for k, v in b.preview.items():
        if isinstance(v, list):
            preview[k] = list(preview.get(k, [])) + list(v)
        else:
            preview[k] = v
    manifest = {
        "name": name,
        "module": spec.module,
        "dims": [round(float(v), 4) for v in (bmax - bmin)],
        "geoMin": [round(float(v), 5) for v in bmin],
        "geoMax": [round(float(v), 5) for v in bmax],
        "bbMin": [round(float(v), 4) for v in amin],
        "bbMax": [round(float(v), 4) for v in amax],
        "bsCentre": [round(float(v), 4) for v in acen],
        "bsRadius": round(arad, 4),
        "lodDist": spec.lod,
        "lodHigh": spec.lod_high if has_med else None,
        "hdTextureDist": spec.hd,
        "flags": flags,
        "static": spec.static,
        "export": spec.export,
        "group": spec.group,
        "tris": stats["tris"],
        "verts": stats["verts"],
        "tris_med": stats["tris_med"],
        "verts_med": stats["verts_med"],
        "budget": spec.budget or None,
        "shaders": [g.shader for g in geoms],
        "textures": tex_summary,
        "screens": sorted(b.screens),
        "mem_est": mem,
        "collision": [{"type": s.kind, "material": s.material, "center": [round(float(v), 4) for v in s.center],
                       "size": [round(float(v), 4) for v in s.size], "axis": s.axis} for s in b.shapes],
        "doc": spec.doc,
        "notes": _jsonable(b.notes),
        "anchors": _jsonable(b.anchors),
        "preview": preview,
        "warnings": list(b.warnings),
        "quick": bool(quick),
        "built_at": round(time.time(), 3),
        "archetype_xml": arch,
    }
    write_json(os.path.join(pdir, "manifest.json"), manifest)
    return manifest


def load_manifest(out_root, name):
    p = os.path.join(out_root, name, "manifest.json")
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None
