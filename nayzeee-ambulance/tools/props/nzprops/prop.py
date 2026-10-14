"""
nzprops.prop - prop registry, the Builder API used by prop definitions, and the per-prop pipeline
(pack -> bake -> tangents -> DDS -> CodeWalker XML -> glTF).

Defining a prop (tools/props/props/*.py):

    from nzprops import *

    @prop("nz_amb_example", atlas=512, lod=60, doc={...})
    def example(b: Builder):
        shell = b.mat("shell", color=(70, 74, 78), spec=0.3, gloss=0.45, bump="stipple")
        b.add(box((0.2, 0.1, 0.05), shell, r=0.006, center=(0, 0, 0.025)))
        dc = DecalCanvas(0.08, 0.03); dc.text(0.04, 0.015, "MONITOR", 0.006)
        b.decal(dc, center=(0, 0.0501, 0.03), normal=(0, 1, 0))
        b.col_box((-0.1, -0.05, 0), (0.1, 0.05, 0.05), "PLASTIC_HIGH_DENSITY")

Layers (picked from each chart's material):
    main   -> normal_spec  (<name>_d DXT1, <name>_n DXT5, <name>_s DXT5 RGB=intensity A=gloss; _n/_s at half size above 1024)
    alpha  -> normal_spec_alpha (<name>_ad DXT5 with alpha, <name>_an, <name>_as)
    glow   -> emissive (<name>_g)                       small LEDs / indicator lights
    screen -> emissive with a fixed-UV texture named by b.screen() (e.g. nz_amb_screen)
    <custom> -> extra normal_spec atlas (<name>_<layer>_d/_n/_s) for big props that need more texels
               than one atlas gives (e.g. labelled supply shelves): declare it with
               @prop(..., layers={"sup": 1024}) and give materials layer="sup".

Preview options (tools/props/preview, never shipped): @prop(..., preview={...})
    views   list of view names used on the contact sheet instead of the global ones
    cams    [{"name", "pos", "target", "fov", "clipZ"?}] extra cameras in GTA prop space
            (clipZ hides everything above that height - a cut-away plan view of a room)
    lights  [{"pos", "intensity", "distance"?, "color"?}] point lights (interiors)
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Callable

import numpy as np
from PIL import Image

from .atlas import chart_px, pack_charts, rasterize
from .bake import AOField, ChartDecal, Decal, bake
from .cwxml import COL_MATERIALS, ColShape, ShaderGeom, archetype_xml, drawable_xml
from .dds import FORMATS, write_dds
from .gltf import write_glb
from .mesh import Geo, normalize
from .paint import DecalCanvas, Mat

FLAG_STATIC = 32                 # archetype flag: static (no physics response)
FLAG_ALPHA_SHADOW = 1 << 31      # unused here, documented for part 2


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
    preview: dict = field(default_factory=dict)   # preview-only cameras / lights / views
    module: str = ""


REGISTRY: dict[str, PropSpec] = {}


def prop(name, **kw):
    def deco(fn):
        register(name, fn, **kw)
        return fn
    return deco


def register(name, fn, **kw):
    if name in REGISTRY:
        raise ValueError(f"prop {name} registered twice")
    REGISTRY[name] = PropSpec(name=name, fn=fn, module=getattr(fn, "__module__", ""), **kw)
    return REGISTRY[name]


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

    # materials --------------------------------------------------------------------------
    def mat(self, name, **kw):
        if name in self.mats:
            return name
        self.mats[name] = Mat(**kw)
        return name

    def mat_from(self, name, m: Mat):
        self.mats[name] = m
        return name

    # geometry ---------------------------------------------------------------------------
    def add(self, *geos):
        for g in geos:
            self.geo += g
        return geos[0] if len(geos) == 1 else geos

    def screen(self, geo: Geo, texname="nz_amb_screen", image: Image.Image | None = None, mult=1.0, size=(512, 256)):
        """Add a screen quad (geometry with fixed 0..1 UVs, see mesh.plane(fixed_uv=True))."""
        key = "screen:" + texname
        for c in geo.charts:
            if c.fixed_uv is None:
                raise ValueError("screen geometry needs fixed UVs (plane(..., fixed_uv=True))")
            c.mat = key
        if image is None:
            image = Image.new("RGB", size, (8, 10, 12))
        self.screens[texname] = (image.convert("RGB").resize(size, Image.LANCZOS), mult, size)
        self.geo += geo
        return geo

    # decals -----------------------------------------------------------------------------
    def decal(self, canvas: DecalCanvas, center, normal, up=(0, 0, 1), depth=0.01, mats=None, min_dot=0.25):
        self.decals.append(Decal(canvas, tuple(center), tuple(normal), tuple(up), depth, None if mats is None else tuple(mats), min_dot))

    def chart_decal(self, canvas: DecalCanvas, tag, u0=0.0, v0=0.0, rot=0, repeat_v=0.0, mats=None, mirror=False):
        """Place a canvas in chart space (metres along the surface) of charts whose tag starts with
        `tag` - e.g. prints that follow a swept strap. rot 90 runs the canvas x along the path."""
        self.chart_decals.append(ChartDecal(canvas, tag, u0, v0, rot, repeat_v, None if mats is None else tuple(mats), mirror))

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


# ---------------------------------------------------------------------------------------------
# pipeline
# ---------------------------------------------------------------------------------------------
def build_prop(spec: PropSpec, out_root: str, quick=False):
    """Build one prop into out_root/<name>/. Returns a manifest dict."""
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

    charts = b.geo.charts
    layers: dict[str, list] = {}
    for c in charts:
        layers.setdefault(_layer_of(b, c.mat), []).append(c)

    all_tris = np.concatenate([c.pos[c.tri] for c in charts])
    ao = None if quick else AOField(all_tris)

    geoms: list[ShaderGeom] = []
    textures = []
    glb_groups = []
    tex_summary = []
    sizes = {"main": spec.atlas, "alpha": spec.alpha_atlas, "glow": spec.glow_atlas}
    sizes.update({k: int(v) for k, v in spec.layers.items()})
    order = ["main"] + sorted(spec.layers) + ["alpha", "glow"]
    for layer in order:
        lc = layers.get(layer)
        if not lc:
            continue
        S = sizes[layer]
        dens, places = pack_charts(lc, S, S, pad=4 if S >= 256 else 2)
        # global arrays
        vpos, vnrm, vuvm, vuv, tri_v, tri_mat, tri_chart, tags, cdens = [], [], [], [], [], [], [], [], []
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
            base += len(c.pos)
        V_pos = np.concatenate(vpos)
        V_nrm = np.concatenate(vnrm)
        V_uvm = np.concatenate(vuvm)
        V_uv = np.concatenate(vuv)
        T_v = np.concatenate(tri_v)
        tid, bary = rasterize(np.concatenate(tri_px), S, S)
        used_mats = {k: v for k, v in b.mats.items() if v.layer == layer}
        imgs = bake(S, S, tid, bary, T_v, V_pos, V_nrm, V_uvm, tri_mat, np.asarray(tri_chart), tags, cdens,
                    used_mats, b.decals, b.chart_decals, ao, alpha_layer=(layer == "alpha"), glow_layer=(layer == "glow"))
        tan = compute_tangents(V_pos, V_nrm, V_uv, T_v)
        prefix = {"main": "", "alpha": "a", "glow": "g"}.get(layer, layer + "_")
        if layer == "glow":
            tn = f"{name}_g"
            mips = write_dds(os.path.join(dds_dir, tn + ".dds"), imgs["diffuse"], "DXT1")
            textures.append((tn, "DIFFUSE", S, S, mips, FORMATS["DXT1"]))
            geoms.append(ShaderGeom("emissive", {"DiffuseSampler": tn}, {"emissiveMultiplier": (spec.glow_mult,)},
                                    V_pos, V_nrm, V_uv, None, T_v))
            imgs["diffuse"].save(os.path.join(prev, tn + ".png"))
            glb_groups.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": None, "idx": T_v,
                               "material": {"kind": "emissive", "name": "glow", "emissive": imgs["diffuse"]}})
            tex_summary.append({"name": tn, "size": S, "density": round(dens, 1)})
            continue
        tn_d, tn_n, tn_s = f"{name}_{prefix}d", f"{name}_{prefix}n", f"{name}_{prefix}s"
        dfmt = "DXT5" if layer == "alpha" else "DXT1"
        md = write_dds(os.path.join(dds_dir, tn_d + ".dds"), imgs["diffuse"], dfmt)
        NS = S if S <= 1024 else S // 2      # sharp normal / spec detail up to 1024, half size above
        nimg = imgs["normal_dx"].resize((NS, NS), Image.LANCZOS) if NS != S else imgs["normal_dx"]
        simg = imgs["spec"].resize((NS, NS), Image.LANCZOS) if NS != S else imgs["spec"]
        mn = write_dds(os.path.join(dds_dir, tn_n + ".dds"), nimg, "DXT5", normal_map=True)
        ms = write_dds(os.path.join(dds_dir, tn_s + ".dds"), simg, "DXT5")
        textures += [(tn_d, "DIFFUSE", S, S, md, FORMATS[dfmt]), (tn_n, "NORMAL", NS, NS, mn, FORMATS["DXT5"]),
                     (tn_s, "SPECULAR", NS, NS, ms, FORMATS["DXT5"])]
        shader = "normal_spec_alpha" if layer == "alpha" else "normal_spec"
        geoms.append(ShaderGeom(shader, {"DiffuseSampler": tn_d, "BumpSampler": tn_n, "SpecSampler": tn_s},
                                {"specularFalloffMult": (spec.falloff,), "specularIntensityMult": (spec.spec_mult,),
                                 "specularFresnel": (0.9,)},
                                V_pos, V_nrm, V_uv, tan, T_v))
        for k, img in (("diffuse", imgs["diffuse"]), ("normal_dx", imgs["normal_dx"]), ("spec", imgs["spec"]), ("mr", imgs["mr"]), ("ao", imgs["ao"])):
            img.save(os.path.join(prev, f"{name}_{prefix}{k}.png"))
        glb_groups.append({"pos": V_pos, "nrm": V_nrm, "uv": V_uv, "tan": tan, "idx": T_v,
                           "material": {"kind": "alpha" if layer == "alpha" else "pbr", "name": layer,
                                        "base": imgs["diffuse"], "normal": imgs["normal_gl"], "mr": imgs["mr"]}})
        tex_summary.append({"name": tn_d, "size": S, "density": round(dens, 1), "coverage": round(imgs["coverage"], 3)})

    # screens (fixed UVs, emissive)
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
        textures.append((texname, "DIFFUSE", size[0], size[1], mips, FORMATS["DXT1"]))
        geoms.append(ShaderGeom("emissive", {"DiffuseSampler": texname}, {"emissiveMultiplier": (mult,)}, pos, nrm, uv, None, idx))
        img.save(os.path.join(prev, texname + ".png"))
        glb_groups.append({"pos": pos, "nrm": nrm, "uv": uv, "tan": None, "idx": idx,
                           "material": {"kind": "emissive", "name": texname, "emissive": img}})
        tex_summary.append({"name": texname, "size": list(size), "screen": True})

    xml, (bmin, bmax, center, radius), (cmin, cmax) = drawable_xml(name, geoms, textures, b.shapes)
    with open(os.path.join(src, name + ".ydr.xml"), "w", encoding="utf-8") as f:
        f.write(xml)
    amin = np.minimum(bmin, cmin)
    amax = np.maximum(bmax, cmax)
    acen = (amin + amax) / 2
    arad = float(np.linalg.norm(amax - acen))
    flags = spec.flags | (FLAG_STATIC if spec.static else 0)
    arch = archetype_xml(name, amin, amax, acen, arad, spec.lod, flags, spec.hd)
    write_glb(os.path.join(pdir, name + ".glb"), name, glb_groups)
    tris = int(sum(len(g.idx) for g in geoms))
    verts = int(sum(len(g.pos) for g in geoms))
    manifest = {
        "name": name,
        "module": spec.module,
        "dims": [round(float(v), 4) for v in (bmax - bmin)],
        "bbMin": [round(float(v), 4) for v in amin],
        "bbMax": [round(float(v), 4) for v in amax],
        "bsCentre": [round(float(v), 4) for v in acen],
        "bsRadius": round(arad, 4),
        "lodDist": spec.lod,
        "hdTextureDist": spec.hd,
        "flags": flags,
        "static": spec.static,
        "tris": tris,
        "verts": verts,
        "shaders": [g.shader for g in geoms],
        "textures": tex_summary,
        "screens": sorted(b.screens),
        "collision": [{"type": s.kind, "material": s.material, "center": [round(float(v), 4) for v in s.center],
                       "size": [round(float(v), 4) for v in s.size], "axis": s.axis} for s in b.shapes],
        "doc": spec.doc,
        "notes": b.notes,
        "preview": spec.preview,
        "archetype_xml": arch,
    }
    with open(os.path.join(pdir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    return manifest
