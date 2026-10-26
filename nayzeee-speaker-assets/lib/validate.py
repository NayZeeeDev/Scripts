"""Re-parse generated CodeWalker XML the way CodeWalker reads it and check it.

    python3 -m lib.validate out/xml          (exit code 1 on any error)

Checks (errors unless marked warning):
* .ydr.xml  root <Drawable>; required nodes; every ShaderFX name exists in
  CodeWalker's ShadersGen9Conversion.xml (data/shaders_gen9.json) and only
  uses real parameter names of that shader; required samplers present; every
  texture name exists in the ytd; RenderBucket/FileName match the shader;
  vertex Layout = GTAV1 with valid semantics that match what the shader needs;
  vertex rows parse with the right number of values, no NaN, colours 0..255,
  <= 65535 vertices; index count % 3 == 0 and indices < vertex count;
  geometry/drawable bounding boxes contain the vertices; LOD distances
  ascending; Flags* match the model blocks present; embedded Bounds parse
  (enum names, material/vertex indices, vertices inside the quantisation box).
* .ytd.xml  enum strings valid (Usage, UsageFlags, Format); names unique and
  lowercase; the .dds next to it (folder named like the ytd) exists, parses
  like DDSIO.GetTexture and matches Width/Height/MipLevels/Format.
* .ytyp.xml CMapTypes / CBaseArchetypeDef node names (case-sensitive meta
  hashes), unique lowercase names, assetName == name, txd exists, a .ydr.xml
  exists per archetype, bbMin/bbMax/bsCentre/bsRadius equal the drawable's.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from typing import Dict, List

import numpy as np

from . import dds as ddsmod
from . import materials as mats

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEXTURE_USAGE = {"UNKNOWN", "DEFAULT", "TERRAIN", "CLOUDDENSITY", "CLOUDNORMAL", "CABLE", "FENCE", "ENVEFF", "SCRIPT",
                 "WATERFLOW", "WATERFOAM", "WATERFOG", "WATEROCEAN", "WATER", "FOAMOPACITY", "FOAM",
                 "DIFFUSEMIPSHARPEN", "DIFFUSEDETAIL", "DIFFUSEDARK", "DIFFUSEALPHAOPAQUE", "DIFFUSE", "DETAIL",
                 "NORMAL", "SPECULAR", "EMISSIVE", "TINTPALETTE", "SKIPPROCESSING", "DONOTOPTIMIZE", "TEST", "COUNT"}
TEXTURE_USAGE_FLAGS = {"NOT_HALF", "HD_SPLIT", "X2", "X4", "Y4", "X8", "X16", "X32", "X64", "Y64", "X128", "X256",
                       "X512", "Y512", "X1024", "Y1024", "X2048", "Y2048", "EMBEDDEDSCRIPTRT", "UNK19", "UNK20",
                       "UNK21", "FLAG_FULL", "MAPS_HALF", "UNK24"}
TEXTURE_FORMATS = {"D3DFMT_A8R8G8B8", "D3DFMT_X8R8G8B8", "D3DFMT_A1R5G5B5", "D3DFMT_A8", "D3DFMT_A8B8G8R8",
                   "D3DFMT_L8", "D3DFMT_DXT1", "D3DFMT_DXT3", "D3DFMT_DXT5", "D3DFMT_ATI1", "D3DFMT_ATI2",
                   "D3DFMT_BC7"}
VERTEX_SEMANTICS = ["Position", "BlendWeights", "BlendIndices", "Normal", "Colour0", "Colour1", "TexCoord0",
                    "TexCoord1", "TexCoord2", "TexCoord3", "TexCoord4", "TexCoord5", "TexCoord6", "TexCoord7",
                    "Tangent", "Binormal"]
# GTAV1 = 0x7755555555996996 -> component type nibble per semantic
GTAV1_TYPES = [(0x7755555555996996 >> (4 * i)) & 0xF for i in range(16)]
COMPONENT_COUNT = {1: 2, 2: 1, 3: 4, 5: 2, 6: 3, 7: 4, 8: 4, 9: 4, 10: 4}
BOUNDS_TYPES = {"None", "Sphere", "Capsule", "Box", "Geometry", "GeometryBVH", "Composite", "Disc", "Cylinder",
                "Cloth"}
COMPOSITE_FLAGS = {"NONE", "UNKNOWN", "MAP_WEAPON", "MAP_DYNAMIC", "MAP_ANIMAL", "MAP_COVER", "MAP_VEHICLE",
                   "VEHICLE_NOT_BVH", "VEHICLE_BVH", "VEHICLE_BOX", "PED", "RAGDOLL", "ANIMAL", "ANIMAL_RAGDOLL",
                   "OBJECT", "OBJECT_ENV_CLOTH", "PLANT", "PROJECTILE", "EXPLOSION", "PICKUP", "FOLIAGE",
                   "FORKLIFT_FORKS", "TEST_WEAPON", "TEST_CAMERA", "TEST_AI", "TEST_SCRIPT", "TEST_VEHICLE_WHEEL",
                   "GLASS", "MAP_RIVER", "SMOKE", "UNSMASHED", "MAP_STAIRS", "MAP_DEEP_SURFACE"}
MATERIAL_FLAGS = {"NONE", "FLAG_STAIRS", "FLAG_NOT_CLIMBABLE", "FLAG_SEE_THROUGH", "FLAG_SHOOT_THROUGH",
                  "FLAG_NOT_COVER", "FLAG_WALKABLE_PATH", "FLAG_NO_CAM_COLLISION", "FLAG_SHOOT_THROUGH_FX",
                  "FLAG_NO_DECAL", "FLAG_NO_NAVMESH", "FLAG_NO_RAGDOLL", "FLAG_VEHICLE_WHEEL", "FLAG_NO_PTFX",
                  "FLAG_TOO_STEEP_FOR_PLAYER", "FLAG_NO_NETWORK_SPAWN", "FLAG_NO_CAM_COLLISION_ALLOW_CLIPPING"}
POLY_TYPES = {"Triangle", "Sphere", "Capsule", "Box", "Cylinder"}
ARCHETYPE_FIELDS = ["lodDist", "flags", "specialAttribute", "bbMin", "bbMax", "bsCentre", "bsRadius",
                    "hdTextureDist", "name", "textureDictionary", "clipDictionary", "drawableDictionary",
                    "physicsDictionary", "assetType", "assetName", "extensions"]
ASSET_TYPES = {"ASSET_TYPE_UNINITIALIZED", "ASSET_TYPE_FRAGMENT", "ASSET_TYPE_DRAWABLE",
               "ASSET_TYPE_DRAWABLEDICTIONARY", "ASSET_TYPE_ASSETLESS"}


class Report:
    def __init__(self):
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.info: Dict[str, dict] = {}

    def err(self, where: str, msg: str):
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str):
        self.warnings.append(f"{where}: {msg}")

    @property
    def ok(self) -> bool:
        return not self.errors


def load_gen9() -> dict:
    with open(os.path.join(ROOT, "data", "shaders_gen9.json"), encoding="utf-8") as f:
        return json.load(f)["shaders"]


def _f(node, attr="value", where="", rep: Report = None) -> float:
    v = node.get(attr) if node is not None else None
    try:
        x = float(v)
    except (TypeError, ValueError):
        if rep is not None:
            rep.err(where, f"attribute {attr!r} missing or not a number ({v!r})")
        return float("nan")
    if not math.isfinite(x) and rep is not None:
        rep.err(where, f"non-finite {attr}={v}")
    return x


def _vec(node, where, rep, comps="xyz"):
    return np.array([_f(node, c, where, rep) for c in comps])


def _child(node, tag, where, rep):
    c = node.find(tag)
    if c is None:
        rep.err(where, f"missing <{tag}>")
    return c


def _flags(text: str, allowed, where, rep, what):
    toks = [t.strip() for t in (text or "").split(",") if t.strip()]
    for t in toks:
        if t not in allowed:
            rep.err(where, f"{what}: invalid enum name {t!r}")
    return toks


# --------------------------------------------------------------------------- ytd
def validate_ytd(path: str, rep: Report) -> Dict[str, dict]:
    where = os.path.basename(path)
    out = {}
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        rep.err(where, f"XML parse error: {e}")
        return out
    if root.tag != "TextureDictionary":
        rep.err(where, f"root is <{root.tag}>, expected <TextureDictionary>")
    folder = path[:-len(".ytd.xml")]
    for i, it in enumerate(root.findall("Item")):
        w = f"{where}[{i}]"
        name = (it.findtext("Name") or "").strip()
        if not name:
            rep.err(w, "texture without <Name>")
            continue
        w = f"{where}:{name}"
        if name != name.lower():
            rep.err(w, "texture names must be lowercase (hashes are of the lowercase name)")
        if name in out:
            rep.err(w, "duplicate texture name")
        usage = it.findtext("Usage")
        if usage not in TEXTURE_USAGE:
            rep.err(w, f"invalid Usage {usage!r}")
        _flags(it.findtext("UsageFlags"), TEXTURE_USAGE_FLAGS, w, rep, "UsageFlags")
        fmt = it.findtext("Format")
        if fmt not in TEXTURE_FORMATS:
            rep.err(w, f"invalid Format {fmt!r}")
        width = int(_f(_child(it, "Width", w, rep), "value", w, rep) or 0)
        height = int(_f(_child(it, "Height", w, rep), "value", w, rep) or 0)
        mips = int(_f(_child(it, "MipLevels", w, rep), "value", w, rep) or 0)
        for tag in ("Unk32", "ExtraFlags"):
            _f(_child(it, tag, w, rep), "value", w, rep)
        fn = it.findtext("FileName") or ""
        fpath = os.path.join(folder, fn)
        if not os.path.isfile(fpath):
            rep.err(w, f"DDS not found: {os.path.relpath(fpath, os.path.dirname(path))}")
        else:
            try:
                info, levels = ddsmod.read_dds(fpath, decode_levels=0)
                if (info["width"], info["height"]) != (width, height):
                    rep.err(w, f"DDS size {info['width']}x{info['height']} != XML {width}x{height}")
                if info["mips"] != mips:
                    rep.err(w, f"DDS mips {info['mips']} != XML MipLevels {mips}")
                if "D3DFMT_" + info["format"] != fmt:
                    rep.err(w, f"DDS format {info['format']} != XML {fmt}")
                for v in (width, height):
                    if v & (v - 1):
                        rep.err(w, f"size {width}x{height} is not a power of two")
                out[name] = {"width": width, "height": height, "mips": mips, "format": fmt,
                             "bytes": os.path.getsize(fpath)}
            except Exception as e:  # noqa: BLE001
                rep.err(w, f"DDS unreadable: {e}")
    return out


# --------------------------------------------------------------------------- ydr
def _parse_rows(text: str):
    rows = [r.strip() for r in (text or "").strip().split("\n")]
    return [r.split() for r in rows if r]


def validate_ydr(path: str, rep: Report, gen9: dict, textures: Dict[str, dict]) -> dict:
    where = os.path.basename(path)
    info = {"tris": {}, "verts": {}}
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        rep.err(where, f"XML parse error: {e}")
        return info
    if root.tag != "Drawable":
        rep.err(where, f"root is <{root.tag}>, expected <Drawable>")
        return info
    name = (root.findtext("Name") or "").strip()
    info["name"] = name
    if name != os.path.basename(path)[:-len(".ydr.xml")]:
        rep.warn(where, f"<Name>{name}</Name> differs from the file name")
    bsc = _vec(_child(root, "BoundingSphereCenter", where, rep), where, rep)
    bsr = _f(_child(root, "BoundingSphereRadius", where, rep), "value", where, rep)
    bbmin = _vec(_child(root, "BoundingBoxMin", where, rep), where, rep)
    bbmax = _vec(_child(root, "BoundingBoxMax", where, rep), where, rep)
    info.update(bb_min=bbmin, bb_max=bbmax, bs_centre=bsc, bs_radius=bsr)
    lods = [_f(_child(root, t, where, rep), "value", where, rep) for t in
            ("LodDistHigh", "LodDistMed", "LodDistLow", "LodDistVlow")]
    if any(lods[i] > lods[i + 1] + 1e-6 for i in range(3)):
        rep.err(where, f"LOD distances not ascending {lods}")
    info["lod_dists"] = lods
    flags = [_f(_child(root, t, where, rep), "value", where, rep) for t in
             ("FlagsHigh", "FlagsMed", "FlagsLow", "FlagsVlow")]
    # shaders
    shaders = []
    sg = _child(root, "ShaderGroup", where, rep)
    sh_node = sg.find("Shaders") if sg is not None else None
    if sh_node is None:
        rep.err(where, "missing ShaderGroup/Shaders")
    else:
        for si, it in enumerate(sh_node.findall("Item")):
            w = f"{where}:shader[{si}]"
            sname = it.findtext("Name") or ""
            sfile = it.findtext("FileName") or ""
            bucket = int(_f(_child(it, "RenderBucket", w, rep), "value", w, rep) or 0)
            shaders.append(sname)
            if sname != sname.lower() or sfile != sfile.lower():
                rep.err(w, "shader Name/FileName must be lowercase (hashed case-sensitively)")
            g = gen9.get(sname)
            if g is None:
                rep.err(w, f"shader {sname!r} does not exist in ShadersGen9Conversion.xml")
                continue
            known = mats.SHADERS.get(sfile)
            if known is None and sfile != g["file"]:
                rep.err(w, f"FileName {sfile!r} is not a known preset of {sname}")
            if known is not None:
                if known.name != sname:
                    rep.err(w, f"FileName {sfile} belongs to shader {known.name}, not {sname}")
                if known.bucket != bucket:
                    rep.err(w, f"RenderBucket {bucket} != {known.bucket} expected for {sfile}")
            if not 0 <= bucket <= 7:
                rep.err(w, f"RenderBucket {bucket} out of range")
            tex_ok = {t.lower() for t in g["textures"]}
            par_ok = {p.lower() for p in g["params"]}
            seen = set()
            params = it.find("Parameters")
            for p in (params.findall("Item") if params is not None else []):
                pn, pt = p.get("name") or "", p.get("type")
                if pn.lower() in seen:
                    rep.err(w, f"duplicate parameter {pn}")
                seen.add(pn.lower())
                if pt == "Texture":
                    if pn.lower() not in tex_ok:
                        rep.err(w, f"{pn!r} is not a texture parameter of {sname}")
                    tname = (p.findtext("Name") or "").strip()
                    if not tname:
                        rep.warn(w, f"texture parameter {pn} has no texture")
                    elif tname not in textures:
                        rep.err(w, f"{pn} -> texture {tname!r} is not in the ytd")
                elif pt == "Vector":
                    if pn.lower() not in par_ok:
                        rep.err(w, f"{pn!r} is not a parameter of {sname}")
                    _vec(p, w + ":" + pn, rep, "xyzw")
                elif pt == "Array":
                    if pn.lower() not in par_ok:
                        rep.err(w, f"{pn!r} is not a parameter of {sname}")
                else:
                    rep.err(w, f"parameter {pn} has invalid type {pt!r}")
            if known is not None:
                for s in known.samplers:
                    if s.lower() not in seen:
                        rep.err(w, f"required sampler {s} missing")
    # models
    present = []
    all_high = []
    for k, tag in enumerate(("DrawableModelsHigh", "DrawableModelsMedium", "DrawableModelsLow",
                             "DrawableModelsVeryLow")):
        node = root.find(tag)
        models = node.findall("Item") if node is not None else []
        present.append(len(models))
        if int(flags[k] or 0) != len(models):
            rep.err(where, f"Flags for {tag} = {flags[k]} but {len(models)} model(s) present")
        tris = verts = 0
        for mi, mdl in enumerate(models):
            w = f"{where}:{tag}[{mi}]"
            for t in ("RenderMask", "Flags", "HasSkin", "BoneIndex", "Unknown1"):
                _f(_child(mdl, t, w, rep), "value", w, rep)
            geoms = mdl.find("Geometries")
            for gi, gm in enumerate(geoms.findall("Item") if geoms is not None else []):
                gw = f"{w}:geom[{gi}]"
                sidx = int(_f(_child(gm, "ShaderIndex", gw, rep), "value", gw, rep) or 0)
                if not 0 <= sidx < len(shaders):
                    rep.err(gw, f"ShaderIndex {sidx} out of range ({len(shaders)} shaders)")
                    continue
                gmin = _vec(_child(gm, "BoundingBoxMin", gw, rep), gw, rep)
                gmax = _vec(_child(gm, "BoundingBoxMax", gw, rep), gw, rep)
                vb = _child(gm, "VertexBuffer", gw, rep)
                ib = _child(gm, "IndexBuffer", gw, rep)
                if vb is None or ib is None:
                    continue
                lay = _child(vb, "Layout", gw, rep)
                if lay is None:
                    continue
                if lay.get("type") != "GTAV1":
                    rep.err(gw, f"Layout type {lay.get('type')!r} (pipeline writes GTAV1)")
                comps = [c.tag for c in lay]
                bad = [c for c in comps if c not in VERTEX_SEMANTICS]
                if bad:
                    rep.err(gw, f"invalid layout semantics {bad}")
                    continue
                order = sorted(comps, key=VERTEX_SEMANTICS.index)
                if order != comps:
                    rep.warn(gw, "layout components not in semantic order (CodeWalker reorders by bit index)")
                sh = shaders[sidx]
                sfile = sh_node.findall("Item")[sidx].findtext("FileName")
                known = mats.SHADERS.get(sfile)
                if known is not None and tuple(order) != tuple(known.layout):
                    rep.err(gw, f"layout {order} does not match {sfile} {list(known.layout)}")
                counts = [COMPONENT_COUNT[GTAV1_TYPES[VERTEX_SEMANTICS.index(c)]] for c in order]
                rows = _parse_rows(vb.findtext("Data"))
                nv = len(rows)
                if nv == 0:
                    rep.err(gw, "no vertices")
                    continue
                if nv > 65535:
                    rep.err(gw, f"{nv} vertices > 65535")
                need = sum(counts)
                lens = {len(r) for r in rows}
                if lens != {need}:
                    rep.err(gw, f"vertex rows have {sorted(lens)} values, layout needs {need}")
                    continue
                arr = np.array(rows, dtype=np.float64)
                if not np.isfinite(arr).all():
                    rep.err(gw, "NaN/inf in vertex data")
                off = 0
                cols = {}
                for c, n in zip(order, counts):
                    cols[c] = arr[:, off:off + n]
                    off += n
                pos = cols["Position"]
                if (pos < gmin - 1e-4).any() or (pos > gmax + 1e-4).any():
                    rep.err(gw, "vertices outside the geometry BoundingBox")
                if k == 0:
                    all_high.append(pos)
                if "Normal" in cols:
                    ln = np.linalg.norm(cols["Normal"], axis=1)
                    if (np.abs(ln - 1) > 0.02).any():
                        rep.err(gw, "normals not unit length")
                if "Colour0" in cols:
                    c0 = cols["Colour0"]
                    if (c0 < 0).any() or (c0 > 255).any() or (c0 != np.round(c0)).any():
                        rep.err(gw, "Colour0 values must be integers 0..255")
                if "Tangent" in cols:
                    tw = cols["Tangent"][:, 3]
                    if (np.abs(np.abs(tw) - 1) > 1e-3).any():
                        rep.err(gw, "tangent w must be +-1")
                idx_text = ib.findtext("Data") or ""
                idx = np.array(re.split(r"\s+", idx_text.strip()), dtype=np.int64) if idx_text.strip() else \
                    np.zeros(0, np.int64)
                if len(idx) % 3:
                    rep.err(gw, f"index count {len(idx)} is not a multiple of 3")
                if len(idx) and (idx.min() < 0 or idx.max() >= nv):
                    rep.err(gw, f"index out of range (max {idx.max()}, {nv} vertices)")
                if len(idx) and idx.max() > 65535:
                    rep.err(gw, "index > 65535 (16-bit index buffer)")
                tris += len(idx) // 3
                verts += nv
        if models:
            info["tris"][tag] = tris
            info["verts"][tag] = verts
    if not present[0]:
        rep.err(where, "no DrawableModelsHigh")
    if all_high:
        P = np.vstack(all_high)
        if (P < bbmin - 1e-4).any() or (P > bbmax + 1e-4).any():
            rep.err(where, "drawable BoundingBox does not contain all High vertices")
        if np.linalg.norm(P - bsc, axis=1).max() > bsr + 1e-4:
            rep.err(where, "BoundingSphere does not contain all High vertices")
    # bounds
    bn = root.find("Bounds")
    if bn is None:
        rep.warn(where, "no embedded Bounds (no collision)")
    else:
        _validate_bounds(bn, f"{where}:Bounds", rep, None, bbmin, bbmax)
    return info


def _validate_bounds(node, where, rep: Report, parent, dbmin, dbmax):
    t = node.get("type")
    if t not in BOUNDS_TYPES:
        rep.err(where, f"invalid Bounds type {t!r}")
        return
    bmin = _vec(_child(node, "BoxMin", where, rep), where, rep)
    bmax = _vec(_child(node, "BoxMax", where, rep), where, rep)
    for tag in ("BoxCenter", "SphereCenter", "Inertia"):
        _vec(_child(node, tag, where, rep), where, rep)
    for tag in ("SphereRadius", "Margin", "Volume", "MaterialIndex", "MaterialColourIndex", "ProceduralID", "RoomID",
                "PedDensity", "UnkFlags", "PolyFlags", "UnkType"):
        _f(_child(node, tag, where, rep), "value", where, rep)
    if (bmin > bmax).any():
        rep.err(where, "BoxMin > BoxMax")
    if parent is not None:
        ct = node.find("CompositeTransform")
        if ct is None:
            rep.err(where, "child without CompositeTransform")
        else:
            vals = np.array((ct.text or "").split(), dtype=float)
            if vals.size != 16 or not np.isfinite(vals).all():
                rep.err(where, "CompositeTransform must be 16 numbers")
        for tag in ("CompositeFlags1", "CompositeFlags2"):
            toks = _flags(node.findtext(tag), COMPOSITE_FLAGS, where, rep, tag)
            if not toks:
                rep.err(where, f"{tag} empty: the child would never collide")
    else:
        slack = 0.1
        if (bmin < dbmin - slack).any() or (bmax > dbmax + slack).any():
            rep.warn(where, "collision extends more than 10 cm beyond the drawable bounding box")
    if t == "Composite":
        ch = node.find("Children")
        items = ch.findall("Item") if ch is not None else []
        if not items:
            rep.err(where, "Composite without children")
        for i, c in enumerate(items):
            _validate_bounds(c, f"{where}[{i}]", rep, node, dbmin, dbmax)
    elif t in ("Geometry", "GeometryBVH"):
        gc = _vec(_child(node, "GeometryCenter", where, rep), where, rep)
        mats_n = node.find("Materials")
        mlist = mats_n.findall("Item") if mats_n is not None else []
        for mi, m in enumerate(mlist):
            mt = _f(_child(m, "Type", where, rep), "value", where, rep)
            if not 0 <= mt <= 255:
                rep.err(where, f"material {mi} Type {mt} out of byte range")
            _flags(m.findtext("Flags"), MATERIAL_FLAGS, where, rep, "material Flags")
        vtxt = node.findtext("Vertices") or ""
        verts = []
        for line in vtxt.strip().split("\n"):
            if line.strip():
                parts = [p for p in line.split(",") if p.strip()]
                if len(parts) != 3:
                    rep.err(where, f"bad vertex row {line.strip()!r}")
                    continue
                verts.append([float(p) for p in parts])
        V = np.array(verts) if verts else np.zeros((0, 3))
        if not np.isfinite(V).all():
            rep.err(where, "NaN in bound vertices")
        half = (bmax - bmin) / 2
        if len(V) and (np.abs(V) > half + 1e-4).any():
            rep.err(where, "bound vertices exceed the quantisation range (BoxMax-BoxMin)/2 around GeometryCenter")
        if np.linalg.norm(gc - (bmin + bmax) / 2) > 1e-4:
            rep.warn(where, "GeometryCenter is not the box centre")
        polys = node.find("Polygons")
        plist = list(polys) if polys is not None else []
        if not plist:
            rep.err(where, "no polygons")
        for p in plist:
            if p.tag not in POLY_TYPES:
                rep.err(where, f"invalid polygon type <{p.tag}>")
                continue
            m = int(p.get("m", "-1"))
            if not 0 <= m < len(mlist):
                rep.err(where, f"{p.tag} material index {m} out of range")
            keys = {"Box": ["v1", "v2", "v3", "v4"], "Cylinder": ["v1", "v2"], "Capsule": ["v1", "v2"],
                    "Sphere": ["v"], "Triangle": ["v1", "v2", "v3"]}[p.tag]
            for k in keys:
                v = int(p.get(k, "-1"))
                if not 0 <= v < len(V):
                    rep.err(where, f"{p.tag} {k}={v} out of range ({len(V)} vertices)")
            if p.tag in ("Cylinder", "Capsule", "Sphere"):
                r = float(p.get("radius", "nan"))
                if not (r > 0 and math.isfinite(r)):
                    rep.err(where, f"{p.tag} radius {r} invalid")


# --------------------------------------------------------------------------- ytyp
def validate_ytyp(path: str, rep: Report, drawables: Dict[str, dict], txd_names) -> List[str]:
    where = os.path.basename(path)
    names = []
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        rep.err(where, f"XML parse error: {e}")
        return names
    if root.tag != "CMapTypes":
        rep.err(where, f"root <{root.tag}>, expected <CMapTypes>")
    for tag in ("extensions", "archetypes", "name", "dependencies", "compositeEntityTypes"):
        _child(root, tag, where, rep)
    arch = root.find("archetypes")
    for i, it in enumerate(arch.findall("Item") if arch is not None else []):
        w = f"{where}[{i}]"
        if it.get("type") != "CBaseArchetypeDef":
            rep.err(w, f"Item type {it.get('type')!r}")
        for f in ARCHETYPE_FIELDS:
            if it.find(f) is None:
                rep.err(w, f"missing <{f}> (meta field names are case-sensitive)")
        name = (it.findtext("name") or "").strip()
        w = f"{where}:{name}"
        if not name or name != name.lower():
            rep.err(w, "archetype name must be lowercase and non-empty")
        if name in names:
            rep.err(w, "duplicate archetype name")
        names.append(name)
        if (it.findtext("assetName") or "") != name:
            rep.err(w, "assetName != name")
        if (it.findtext("assetType") or "") not in ASSET_TYPES:
            rep.err(w, f"invalid assetType {it.findtext('assetType')!r}")
        txd = it.findtext("textureDictionary") or ""
        if txd not in txd_names:
            rep.err(w, f"textureDictionary {txd!r} has no .ytd.xml")
        lod = _f(it.find("lodDist"), "value", w, rep)
        if not lod > 0:
            rep.err(w, "lodDist must be > 0")
        int(_f(it.find("flags"), "value", w, rep))
        _f(it.find("hdTextureDist"), "value", w, rep)
        bbmin = _vec(it.find("bbMin"), w, rep)
        bbmax = _vec(it.find("bbMax"), w, rep)
        bsc = _vec(it.find("bsCentre"), w, rep)
        bsr = _f(it.find("bsRadius"), "value", w, rep)
        d = drawables.get(name)
        if d is None:
            rep.err(w, f"no {name}.ydr.xml for this archetype")
            continue
        for lbl, a, b in (("bbMin", bbmin, d["bb_min"]), ("bbMax", bbmax, d["bb_max"]),
                          ("bsCentre", bsc, d["bs_centre"])):
            if np.abs(a - b).max() > 1e-4:
                rep.err(w, f"{lbl} {a} != drawable {b}")
        if abs(bsr - d["bs_radius"]) > 1e-4:
            rep.err(w, f"bsRadius {bsr} != drawable {d['bs_radius']}")
        if lod < d["lod_dists"][0] and d["lod_dists"][0] < 9998:
            rep.warn(w, "archetype lodDist is shorter than the drawable LodDistHigh")
    return names


# --------------------------------------------------------------------------- glb
_GL_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_GL_COMPS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
_GL_DTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def validate_glb(path: str, rep: Report) -> dict:
    """Structural glTF 2.0 checks: chunks, views, accessors, attributes, indices, images."""
    import io
    import struct
    from PIL import Image
    where = os.path.basename(path)
    data = open(path, "rb").read()
    info = {}
    try:
        magic, ver, total = struct.unpack_from("<4sII", data, 0)
        if magic != b"glTF" or ver != 2 or total != len(data):
            rep.err(where, "bad GLB header")
            return info
        jl, jt = struct.unpack_from("<I4s", data, 12)
        if jt != b"JSON" or jl % 4:
            rep.err(where, "bad JSON chunk")
        js = json.loads(data[20:20 + jl])
        bl, bt = struct.unpack_from("<I4s", data, 20 + jl)
        if bt != b"BIN\x00" or bl % 4:
            rep.err(where, "bad BIN chunk")
        binc = data[28 + jl:28 + jl + bl]
    except Exception as e:  # noqa: BLE001
        rep.err(where, f"unreadable: {e}")
        return info
    if js.get("asset", {}).get("version") != "2.0":
        rep.err(where, "asset.version must be 2.0")
    views = js.get("bufferViews", [])
    for i, v in enumerate(views):
        if v["byteOffset"] + v["byteLength"] > len(binc) or v["byteOffset"] % 4:
            rep.err(where, f"bufferView {i} out of range / misaligned")

    def acc(i):
        a = js["accessors"][i]
        v = views[a["bufferView"]]
        n = a["count"] * _GL_COMPS[a["type"]]
        size = n * _GL_SIZES[a["componentType"]]
        if size > v["byteLength"]:
            rep.err(where, f"accessor {i} larger than its bufferView")
            return None
        arr = np.frombuffer(binc, dtype=_GL_DTYPE[a["componentType"]], count=n, offset=v["byteOffset"])
        return arr.reshape(a["count"], _GL_COMPS[a["type"]]), a

    nmat = len(js.get("materials", []))
    ntex = len(js.get("textures", []))
    tris = 0
    for mi, m in enumerate(js.get("meshes", [])):
        for pi, pr in enumerate(m["primitives"]):
            w = f"{where}:mesh{mi}.prim{pi}"
            at = pr["attributes"]
            for req in ("POSITION", "NORMAL", "TEXCOORD_0"):
                if req not in at:
                    rep.err(w, f"missing {req}")
            pos = acc(at["POSITION"])
            if pos is None:
                continue
            P, pa = pos
            if "min" not in pa or "max" not in pa:
                rep.err(w, "POSITION accessor needs min/max")
            elif (np.abs(P.min(axis=0) - pa["min"]) > 1e-5).any() or (np.abs(P.max(axis=0) - pa["max"]) > 1e-5).any():
                rep.err(w, "POSITION min/max do not match the data")
            nv = len(P)
            for key in at:
                r = acc(at[key])
                if r is not None and len(r[0]) != nv:
                    rep.err(w, f"{key} count {len(r[0])} != POSITION count {nv}")
                if r is not None and r[0].dtype.kind == "f" and not np.isfinite(r[0]).all():
                    rep.err(w, f"{key} has NaN/inf")
            if "NORMAL" in at:
                N = acc(at["NORMAL"])[0]
                if (np.abs(np.linalg.norm(N, axis=1) - 1) > 1e-3).any():
                    rep.err(w, "NORMAL not unit length")
            if "TANGENT" in at:
                T = acc(at["TANGENT"])[0]
                if (np.abs(np.abs(T[:, 3]) - 1) > 1e-6).any() or (np.abs(np.linalg.norm(T[:, :3], axis=1) - 1) > 1e-3).any():
                    rep.err(w, "TANGENT must be unit xyz with w = +-1")
            if "indices" in pr:
                I = acc(pr["indices"])[0].reshape(-1)
                if len(I) % 3 or (len(I) and I.max() >= nv):
                    rep.err(w, "bad index buffer")
                tris += len(I) // 3
            if pr.get("material", 0) >= nmat:
                rep.err(w, "material index out of range")
    for mi, m in enumerate(js.get("materials", [])):
        refs = [m.get("normalTexture"), m.get("emissiveTexture"), m.get("occlusionTexture"),
                m.get("pbrMetallicRoughness", {}).get("baseColorTexture"),
                m.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")]
        for r in refs:
            if r is not None and not 0 <= r["index"] < ntex:
                rep.err(where, f"material {mi} texture index out of range")
    for ii, im in enumerate(js.get("images", [])):
        v = views[im["bufferView"]]
        try:
            Image.open(io.BytesIO(binc[v["byteOffset"]:v["byteOffset"] + v["byteLength"]])).verify()
        except Exception as e:  # noqa: BLE001
            rep.err(where, f"image {ii} is not a valid {im.get('mimeType')}: {e}")
    info["tris"] = tris
    return info


# --------------------------------------------------------------------------- entry point
def validate_dir(xml_dir: str) -> Report:
    rep = Report()
    gen9 = load_gen9()
    files = sorted(os.listdir(xml_dir)) if os.path.isdir(xml_dir) else []
    ytds = [f for f in files if f.endswith(".ytd.xml")]
    ydrs = [f for f in files if f.endswith(".ydr.xml")]
    ytyps = [f for f in files if f.endswith(".ytyp.xml")]
    if not ytds:
        rep.err(xml_dir, "no .ytd.xml found")
    textures: Dict[str, dict] = {}
    for f in ytds:
        textures.update(validate_ytd(os.path.join(xml_dir, f), rep))
    rep.info["textures"] = textures
    drawables = {}
    for f in ydrs:
        info = validate_ydr(os.path.join(xml_dir, f), rep, gen9, textures)
        drawables[f[:-len(".ydr.xml")]] = info
    rep.info["drawables"] = drawables
    archetypes = []
    for f in ytyps:
        archetypes += validate_ytyp(os.path.join(xml_dir, f), rep, drawables, [t[:-len(".ytd.xml")] for t in ytds])
    for d in drawables:
        if ytyps and d not in archetypes:
            rep.warn(d, "drawable has no archetype in the ytyp")
    rep.info["archetypes"] = archetypes
    glb_dir = os.path.join(os.path.dirname(os.path.abspath(xml_dir)), "glb")
    if os.path.isdir(glb_dir):
        rep.info["glb"] = {f: validate_glb(os.path.join(glb_dir, f), rep)
                           for f in sorted(os.listdir(glb_dir)) if f.endswith(".glb")}
    return rep


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    xml_dir = argv[0] if argv else os.path.join(ROOT, "out", "xml")
    rep = validate_dir(xml_dir)
    for w in rep.warnings:
        print("WARN ", w)
    for e in rep.errors:
        print("ERROR", e)
    n = len(rep.info.get("drawables", {}))
    print(f"validate: {n} drawable(s), {len(rep.info.get('textures', {}))} texture(s), "
          f"{len(rep.info.get('archetypes', []))} archetype(s), {len(rep.info.get('glb', {}))} glb: "
          f"{'OK' if rep.ok else str(len(rep.errors)) + ' error(s)'}, {len(rep.warnings)} warning(s)")
    return 0 if rep.ok else 1


if __name__ == "__main__":
    sys.exit(main())
