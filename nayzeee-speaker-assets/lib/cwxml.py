"""CodeWalker XML writers: <model>.ydr.xml, <txd>.ytd.xml (+ .dds folder), <name>.ytyp.xml.

The element names, attribute style and value formats mirror CodeWalker's own
WriteXml/ReadXml (CodeWalker.Core/GameFiles/Resources/Drawable.cs, Texture.cs,
Bounds.cs, MetaTypes): one-space indentation, ``<Tag value="..." />`` for
scalars, ``x="" y="" z=""`` vectors, vertex rows with components separated by
three spaces, index rows of 24.

Import order in CodeWalker (RPF Explorer > Import XML): the .ytd.xml first
(it reads ``<FileName>`` .dds files from the folder named like the ytd, next
to the xml), then each .ydr.xml, then the .ytyp.xml.

Design notes
------------
* Textures are NOT embedded in the drawables; shader texture parameters only
  carry the texture name and the game resolves them through the archetype's
  txd (``nayzeee_console_texture``, see lib.textures.TXD_NAME).
* One shader per material; one geometry per material per LOD model (split
  when a geometry would exceed 65535 vertices -- the index buffer is 16-bit).
* Collision: a BoundComposite whose single GeometryBVH child holds one
  primitive polygon per declared shape (Box / Cylinder / Sphere / Capsule).
  Primitives inside a BVH can have any orientation and need no composite
  transforms, which avoids CodeWalker computing child AABBs from rotated
  local boxes.
"""
from __future__ import annotations

import os
from typing import Dict, List, Sequence
from xml.sax.saxutils import escape

import numpy as np

from . import materials as mats
from . import spec as specmod
from .mesh import Mesh, group_by_material, parts_bounds

XML_HEADER = '<?xml version="1.0" encoding="UTF-8"?>'
MAX_VERTS = 65535
BVH_MARGIN = 0.04

# composite child flags: Sollumz "General (Default)" preset (type = map collision
# classes, include = everything that should collide with the prop)
COMPOSITE_FLAGS1 = ["MAP_WEAPON", "MAP_DYNAMIC", "MAP_ANIMAL", "MAP_COVER", "MAP_VEHICLE"]
COMPOSITE_FLAGS2 = ["VEHICLE_NOT_BVH", "VEHICLE_BVH", "PED", "RAGDOLL", "ANIMAL", "ANIMAL_RAGDOLL", "OBJECT",
                    "PLANT", "PROJECTILE", "EXPLOSION", "FORKLIFT_FORKS", "TEST_WEAPON", "TEST_CAMERA", "TEST_AI",
                    "TEST_SCRIPT", "TEST_VEHICLE_WHEEL", "GLASS"]


# --------------------------------------------------------------------------- formatting
def ff(x) -> str:
    """Scalar float like CodeWalker's FloatUtil.ToString: float32, shortest round-trip, invariant."""
    f = np.float32(x)
    if not np.isfinite(f):
        raise ValueError(f"non-finite value {x!r}")
    if f == 0:
        return "0"
    return np.format_float_positional(f, unique=True, trim="-")


def fv3(v) -> str:
    return f'x="{ff(v[0])}" y="{ff(v[1])}" z="{ff(v[2])}"'


def fv4(v) -> str:
    return f'x="{ff(v[0])}" y="{ff(v[1])}" z="{ff(v[2])}" w="{ff(v[3])}"'


def _col_strings(a: np.ndarray, fmt: str = "%.7g") -> np.ndarray:
    a = np.asarray(a, dtype=np.float64)
    a = np.where(np.abs(a) < 1e-9, 0.0, a)
    s = np.char.mod(fmt, a)
    return np.where(s == "-0", "0", s)


class _W:
    """Tiny indented line writer."""

    def __init__(self):
        self.lines: List[str] = [XML_HEADER]

    def line(self, ind: int, text: str):
        self.lines.append(" " * ind + text)

    def value(self, ind: int, tag: str, val):
        self.line(ind, f'<{tag} value="{val}" />')

    def text(self, ind: int, tag: str, val: str):
        if val:
            self.line(ind, f"<{tag}>{escape(val)}</{tag}>")
        else:
            self.line(ind, f"<{tag} />")

    def open(self, ind: int, tag: str, attrs: str = ""):
        self.line(ind, f"<{tag}{(' ' + attrs) if attrs else ''}>")

    def close(self, ind: int, tag: str):
        self.line(ind, f"</{tag}>")

    def raw(self, text: str):
        self.lines.append(text)

    def result(self) -> str:
        return "\n".join(self.lines) + "\n"


# --------------------------------------------------------------------------- geometry export
def _vertex_columns(mesh: Mesh, layout: Sequence[str]):
    """Attribute arrays (float64) per layout component, plus their text format."""
    cols = []
    for comp in layout:
        if comp == "Position":
            cols.append((mesh.positions, "%.7g"))
        elif comp == "Normal":
            cols.append((mesh.normals, "%.6g"))
        elif comp == "Colour0":
            cols.append((np.clip(np.rint(mesh.colors * 255), 0, 255), "%d"))
        elif comp == "TexCoord0":
            cols.append((mesh.uvs, "%.7g"))
        elif comp == "Tangent":
            cols.append((mesh.ensure_tangents(), "%.6g"))
        else:
            raise ValueError(f"unsupported vertex component {comp}")
    return cols


def geometry_chunks(mesh: Mesh, layout: Sequence[str]):
    """Dedupe vertices and split into <= 65535-vertex chunks.

    Returns a list of (columns: list[(array, fmt)], indices (M,3) uint16-range ints).
    """
    cols = _vertex_columns(mesh, layout)
    quant = []
    for arr, fmt in cols:
        q = np.rint(arr * (1.0 if fmt == "%d" else 1e6)).astype(np.int64)
        quant.append(q.reshape(len(arr), -1))
    key = np.hstack(quant)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    order = np.argsort(first, kind="stable")              # keep original vertex order
    rank = np.empty_like(order)
    rank[order] = np.arange(len(order))
    vsrc = first[order]
    tris = rank[inv][mesh.indices]
    ucols = [(arr[vsrc], fmt) for arr, fmt in cols]
    nverts = len(vsrc)
    if nverts <= MAX_VERTS:
        return [(ucols, tris)]
    chunks = []
    local = {}
    ctris = []
    for t in tris:
        new = [v for v in t if v not in local]
        if len(local) + len(set(new)) > MAX_VERTS:
            chunks.append((local, ctris))
            local, ctris = {}, []
        lt = []
        for v in t:
            if v not in local:
                local[v] = len(local)
            lt.append(local[v])
        ctris.append(lt)
    chunks.append((local, ctris))
    out = []
    for local, ctris in chunks:
        src = np.empty(len(local), dtype=np.int64)
        for g, l in local.items():
            src[l] = g
        out.append(([(arr[src], fmt) for arr, fmt in ucols], np.array(ctris, dtype=np.int64)))
    return out


def _write_vertex_data(w: _W, ind: int, cols):
    parts = []
    for arr, fmt in cols:
        a = arr if arr.ndim == 2 else arr[:, None]
        s = _col_strings(a, fmt)
        parts.append([" ".join(row) for row in s])
    pad = " " * ind
    rows = ["   ".join(p[i] for p in parts) for i in range(len(parts[0]))]
    w.raw("\n".join(pad + r for r in rows))


def _write_indices(w: _W, ind: int, tris: np.ndarray):
    flat = tris.reshape(-1)
    w.open(ind, "Data")
    pad = " " * (ind + 1)
    s = flat.astype(str)
    w.raw("\n".join(pad + " ".join(s[i:i + 24]) for i in range(0, len(s), 24)))
    w.close(ind, "Data")


# --------------------------------------------------------------------------- bounds
def _bounds_common(w: _W, ind: int, bmin, bmax, centroid, radius, cg, margin, volume, inertia, material_index=0):
    w.line(ind, f"<BoxMin {fv3(bmin)} />")
    w.line(ind, f"<BoxMax {fv3(bmax)} />")
    w.line(ind, f"<BoxCenter {fv3(centroid)} />")
    w.line(ind, f"<SphereCenter {fv3(cg)} />")
    w.value(ind, "SphereRadius", ff(radius))
    w.value(ind, "Margin", ff(margin))
    w.value(ind, "Volume", ff(volume))
    w.line(ind, f"<Inertia {fv3(inertia)} />")
    w.value(ind, "MaterialIndex", material_index)
    w.value(ind, "MaterialColourIndex", 0)
    w.value(ind, "ProceduralID", 0)
    w.value(ind, "RoomID", 0)
    w.value(ind, "PedDensity", 0)
    w.value(ind, "UnkFlags", 0)
    w.value(ind, "PolyFlags", 0)
    w.value(ind, "UnkType", 1)


def collision_summary(shapes) -> dict:
    """Numbers used for the embedded bounds (also handy for layout.json)."""
    lo = np.min([s.aabb()[0] for s in shapes], axis=0)
    hi = np.max([s.aabb()[1] for s in shapes], axis=0)
    centre = (lo + hi) / 2
    radius = 0.0
    for s in shapes:
        for p, r in s.bounding_points():
            radius = max(radius, float(np.linalg.norm(p - centre)) + r)
    vol, cg, inertia = specmod.collision_mass_properties(shapes)
    return {"min": lo, "max": hi, "centre": centre, "radius": radius, "volume": vol, "cg": cg, "inertia": inertia}


def write_bounds(w: _W, ind: int, shapes):
    """Embedded <Bounds type="Composite"> with one GeometryBVH child of primitive polygons."""
    shapes = list(shapes)
    s = collision_summary(shapes)
    bmin, bmax = s["min"] - BVH_MARGIN, s["max"] + BVH_MARGIN
    gcen = (bmin + bmax) / 2
    centroid = gcen
    radius = s["radius"] + BVH_MARGIN
    mat_names: List[str] = []
    verts: List[np.ndarray] = []
    polys: List[str] = []

    def vid(p):
        verts.append(np.asarray(p, float))
        return len(verts) - 1

    for sh in shapes:
        mname = sh.material or "PLASTIC"
        if mname not in mat_names:
            mat_names.append(mname)
        m = mat_names.index(mname)
        if isinstance(sh, specmod.Box):
            ids = [vid(p) for p in sh.poly_vertices()]
            polys.append(f'<Box m="{m}" v1="{ids[0]}" v2="{ids[1]}" v3="{ids[2]}" v4="{ids[3]}" />')
        elif isinstance(sh, specmod.Cylinder):
            a, b = vid(sh.p1), vid(sh.p2)
            polys.append(f'<Cylinder m="{m}" v1="{a}" v2="{b}" radius="{ff(sh.radius)}" />')
        elif isinstance(sh, specmod.Capsule):
            a, b = vid(sh.p1), vid(sh.p2)
            polys.append(f'<Capsule m="{m}" v1="{a}" v2="{b}" radius="{ff(sh.radius)}" />')
        elif isinstance(sh, specmod.Sphere):
            a = vid(sh.center)
            polys.append(f'<Sphere m="{m}" v="{a}" radius="{ff(sh.radius)}" />')
        else:
            raise TypeError(f"unsupported collision shape {sh!r}")
    w.open(ind, "Bounds", 'type="Composite"')
    _bounds_common(w, ind + 1, bmin, bmax, centroid, radius, s["cg"], 0.0, s["volume"], s["inertia"])
    w.open(ind + 1, "Children")
    ci = ind + 2
    w.open(ci, "Item", 'type="GeometryBVH"')
    c = ci + 1
    _bounds_common(w, c, bmin, bmax, centroid, radius, s["cg"], BVH_MARGIN, s["volume"], s["inertia"])
    w.open(c, "CompositeTransform")
    for row in np.eye(4):
        w.line(c + 1, " ".join(ff(v) for v in row))
    w.close(c, "CompositeTransform")
    w.text(c, "CompositeFlags1", ", ".join(COMPOSITE_FLAGS1))
    w.text(c, "CompositeFlags2", ", ".join(COMPOSITE_FLAGS2))
    w.line(c, f"<GeometryCenter {fv3(gcen)} />")
    w.value(c, "UnkFloat1", "0")
    w.value(c, "UnkFloat2", "0")
    w.open(c, "Materials")
    for mname in mat_names:
        w.open(c + 1, "Item")
        w.value(c + 2, "Type", mats.COLLISION_MATERIALS[mname])
        w.value(c + 2, "ProceduralID", 0)
        w.value(c + 2, "RoomID", 0)
        w.value(c + 2, "PedDensity", 0)
        w.text(c + 2, "Flags", "NONE")
        w.value(c + 2, "MaterialColourIndex", 0)
        w.value(c + 2, "Unk", 0)
        w.close(c + 1, "Item")
    w.close(c, "Materials")
    w.open(c, "Vertices")
    for v in verts:
        r = v - gcen
        w.line(c + 1, f"{ff(r[0])}, {ff(r[1])}, {ff(r[2])}")
    w.close(c, "Vertices")
    w.open(c, "Polygons")
    for p in polys:
        w.line(c + 1, p)
    w.close(c, "Polygons")
    w.close(ci, "Item")
    w.close(ind + 1, "Children")
    w.close(ind, "Bounds")


# --------------------------------------------------------------------------- drawable
LOD_TAGS = (("High", "DrawableModelsHigh"), ("Medium", "DrawableModelsMedium"),
            ("Low", "DrawableModelsLow"), ("VeryLow", "DrawableModelsVeryLow"))


def ydr_xml(name: str, lods: Dict[str, list], collision, lod: "specmod.LodSettings") -> str:
    """Build a CodeWalker Drawable XML.

    lods: {'High': parts, 'Medium': parts (optional)} -- parts are Meshes with materials.
    """
    groups = {k: group_by_material(v) for k, v in lods.items() if v}
    if "High" not in groups:
        raise ValueError(f"{name}: High LOD missing")
    shader_mats: List[str] = []
    for k, _ in LOD_TAGS:
        for mname in groups.get(k, {}):
            if mname not in shader_mats:
                shader_mats.append(mname)
    lo, hi, bsc, bsr = parts_bounds(lods["High"])
    has_med = "Medium" in groups
    dist_high = lod.high_dist if has_med else 9998.0
    w = _W()
    w.open(0, "Drawable")
    w.text(1, "Name", name)
    w.line(1, f"<BoundingSphereCenter {fv3(bsc)} />")
    w.value(1, "BoundingSphereRadius", ff(bsr))
    w.line(1, f"<BoundingBoxMin {fv3(lo)} />")
    w.line(1, f"<BoundingBoxMax {fv3(hi)} />")
    w.value(1, "LodDistHigh", ff(dist_high))
    w.value(1, "LodDistMed", ff(lod.med_dist if has_med else 9998.0))
    w.value(1, "LodDistLow", ff(9998.0))
    w.value(1, "LodDistVlow", ff(9998.0))
    for (k, _), tag in zip(LOD_TAGS, ("FlagsHigh", "FlagsMed", "FlagsLow", "FlagsVlow")):
        w.value(1, tag, 1 if k in groups else 0)
    # shaders
    w.open(1, "ShaderGroup")
    w.open(2, "Shaders")
    for mname in shader_mats:
        m = mats.get(mname)
        sd = m.shader_def
        w.open(3, "Item")
        w.text(4, "Name", sd.name)
        w.text(4, "FileName", sd.file)
        w.value(4, "RenderBucket", sd.bucket)
        w.open(4, "Parameters")
        for pname, ptype, val in m.shader_params():
            if ptype == "Texture":
                w.open(5, "Item", f'name="{pname}" type="Texture"')
                w.text(6, "Name", val)
                w.close(5, "Item")
            else:
                w.line(5, f'<Item name="{pname}" type="Vector" {fv4(val)} />')
        w.close(4, "Parameters")
        w.close(3, "Item")
    w.close(2, "Shaders")
    w.close(1, "ShaderGroup")
    # models
    for k, tag in LOD_TAGS:
        if k not in groups:
            continue
        w.open(1, tag)
        w.open(2, "Item")
        w.value(3, "RenderMask", 255)
        w.value(3, "Flags", 0)
        w.value(3, "HasSkin", 0)
        w.value(3, "BoneIndex", 0)
        w.value(3, "Unknown1", 0)
        w.open(3, "Geometries")
        for mname, mesh in groups[k].items():
            sd = mats.get(mname).shader_def
            for cols, tris in geometry_chunks(mesh, sd.layout):
                pos = cols[0][0]
                w.open(4, "Item")
                w.value(5, "ShaderIndex", shader_mats.index(mname))
                gmin, gmax = pos.min(axis=0), pos.max(axis=0)
                w.line(5, f"<BoundingBoxMin {fv4(list(gmin) + [0.0])} />")
                w.line(5, f"<BoundingBoxMax {fv4(list(gmax) + [0.0])} />")
                w.open(5, "VertexBuffer")
                w.value(6, "Flags", 0)
                w.open(6, "Layout", 'type="GTAV1"')
                for comp in sd.layout:
                    w.line(7, f"<{comp} />")
                w.close(6, "Layout")
                w.open(6, "Data")
                _write_vertex_data(w, 7, cols)
                w.close(6, "Data")
                w.close(5, "VertexBuffer")
                w.open(5, "IndexBuffer")
                _write_indices(w, 6, tris)
                w.close(5, "IndexBuffer")
                w.close(4, "Item")
        w.close(3, "Geometries")
        w.close(2, "Item")
        w.close(1, tag)
    if collision:
        write_bounds(w, 1, collision)
    w.close(0, "Drawable")
    return w.result()


# --------------------------------------------------------------------------- texture dictionary
def ytd_xml(entries) -> str:
    """entries: iterable of dicts {name, width, height, mips, format ('DXT1'|'DXT5'), usage}."""
    w = _W()
    entries = list(entries)
    if not entries:
        w.line(0, "<TextureDictionary />")
        return w.result()
    w.open(0, "TextureDictionary")
    for e in entries:
        w.open(1, "Item")
        w.text(2, "Name", e["name"])
        w.value(2, "Unk32", 128)
        w.text(2, "Usage", e.get("usage", "DIFFUSE"))
        w.text(2, "UsageFlags", "UNK24")
        w.value(2, "ExtraFlags", 0)
        w.value(2, "Width", e["width"])
        w.value(2, "Height", e["height"])
        w.value(2, "MipLevels", e["mips"])
        w.text(2, "Format", "D3DFMT_" + e["format"])
        w.text(2, "FileName", e["name"] + ".dds")
        w.close(1, "Item")
    w.close(0, "TextureDictionary")
    return w.result()


# --------------------------------------------------------------------------- archetypes
def ytyp_xml(name: str, archetypes) -> str:
    """archetypes: iterable of dicts {name, txd, lod_dist, flags, bb_min, bb_max, bs_centre, bs_radius, hd_dist}."""
    w = _W()
    w.open(0, "CMapTypes")
    w.text(1, "extensions", "")
    w.open(1, "archetypes")
    for a in archetypes:
        w.open(2, "Item", 'type="CBaseArchetypeDef"')
        w.value(3, "lodDist", ff(a["lod_dist"]))
        w.value(3, "flags", int(a["flags"]))
        w.value(3, "specialAttribute", 0)
        w.line(3, f"<bbMin {fv3(a['bb_min'])} />")
        w.line(3, f"<bbMax {fv3(a['bb_max'])} />")
        w.line(3, f"<bsCentre {fv3(a['bs_centre'])} />")
        w.value(3, "bsRadius", ff(a["bs_radius"]))
        w.value(3, "hdTextureDist", ff(a["hd_dist"]))
        w.text(3, "name", a["name"])
        w.text(3, "textureDictionary", a["txd"])
        w.text(3, "clipDictionary", "")
        w.text(3, "drawableDictionary", "")
        w.text(3, "physicsDictionary", "")
        w.text(3, "assetType", "ASSET_TYPE_DRAWABLE")
        w.text(3, "assetName", a["name"])
        w.text(3, "extensions", "")
        w.close(2, "Item")
    w.close(1, "archetypes")
    w.text(1, "name", name)
    w.text(1, "dependencies", "")
    w.text(1, "compositeEntityTypes", "")
    w.close(0, "CMapTypes")
    return w.result()


def write_text(path: str, text: str):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
