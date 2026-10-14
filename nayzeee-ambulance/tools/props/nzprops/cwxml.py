"""
nzprops.cwxml - CodeWalker XML writers: drawable (.ydr.xml) with embedded textures and composite
collision, and the archetype file (.ytyp.xml) for every prop.

Shader parameter lists follow the game's own order (same as Sollumz' shader definitions).
Collision: BoundComposite with Box (identity transform, extents in prop space) and Cylinder
children (local extents along the bound's Y axis + a composite transform), the same convention
Sollumz writes and CodeWalker round-trips.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

# name -> (file name, render bucket, [(param, 'tex' | default floats)])
SHADERS = {
    "normal_spec": ("normal_spec.sps", 0, [
        ("DiffuseSampler", "tex"), ("BumpSampler", "tex"), ("SpecSampler", "tex"),
        ("HardAlphaBlend", (1,)), ("useTessellation", (0,)), ("wetnessMultiplier", (1,)), ("bumpiness", (1,)),
        ("specMapIntMask", (1, 0, 0)), ("specularIntensityMult", (1,)), ("specularFalloffMult", (100,)),
        ("specularFresnel", (0.75,))]),
    "normal_spec_alpha": ("normal_spec_alpha.sps", 1, [
        ("DiffuseSampler", "tex"), ("BumpSampler", "tex"), ("SpecSampler", "tex"),
        ("HardAlphaBlend", (1,)), ("useTessellation", (0,)), ("wetnessMultiplier", (1,)), ("bumpiness", (1,)),
        ("specMapIntMask", (1, 0, 0)), ("specularIntensityMult", (1,)), ("specularFalloffMult", (100,)),
        ("specularFresnel", (0.75,))]),
    "emissive": ("emissive.sps", 0, [
        ("DiffuseSampler", "tex"), ("matMaterialColorScale", (1, 0, 0, 1)), ("HardAlphaBlend", (1,)),
        ("useTessellation", (0,)), ("emissiveMultiplier", (1,)), ("globalAnimUV1", (0, 1, 0)), ("globalAnimUV0", (1, 0, 0))]),
    "default": ("default.sps", 0, [
        ("DiffuseSampler", "tex"), ("matMaterialColorScale", (1, 0, 0, 1)), ("HardAlphaBlend", (1,)),
        ("useTessellation", (0,)), ("wetnessMultiplier", (1,)), ("globalAnimUV1", (0, 1, 0)), ("globalAnimUV0", (1, 0, 0))]),
    "spec": ("spec.sps", 0, [
        ("DiffuseSampler", "tex"), ("SpecSampler", "tex"), ("HardAlphaBlend", (1,)), ("useTessellation", (0,)),
        ("wetnessMultiplier", (1,)), ("specMapIntMask", (1, 0, 0)), ("specularIntensityMult", (1,)),
        ("specularFalloffMult", (100,)), ("specularFresnel", (0.97,)), ("globalAnimUV1", (0, 1, 0)), ("globalAnimUV0", (1, 0, 0))]),
}
TANGENT_SHADERS = {"normal_spec", "normal_spec_alpha"}

# collision materials (index into the game's materials.dat)
COL_MATERIALS = {
    "DEFAULT": 0, "METAL_SOLID_SMALL": 55, "METAL_SOLID_MEDIUM": 56, "METAL_HOLLOW_SMALL": 58,
    "METAL_HOLLOW_MEDIUM": 59, "FIBREGLASS": 84, "PLASTIC": 86, "PLASTIC_HOLLOW": 87,
    "PLASTIC_HIGH_DENSITY": 88, "PLASTIC_CLEAR": 89, "PLASTIC_HOLLOW_CLEAR": 90,
    "RUBBER": 93, "RUBBER_HOLLOW": 94, "CLOTH": 100, "FOAM": 106, "LEATHER": 109,
}
COMPOSITE_FLAGS1 = "MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE"
COMPOSITE_FLAGS2 = ("VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, "
                    "PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, "
                    "TEST_VEHICLE_WHEEL, GLASS")


def f6(x: float) -> str:
    s = f"{float(x):.6f}"
    return "0.000000" if s == "-0.000000" else s


def vattr(v):
    return f'x="{f6(v[0])}" y="{f6(v[1])}" z="{f6(v[2])}"'


# ---------------------------------------------------------------------------------------------
# collision
# ---------------------------------------------------------------------------------------------
@dataclass
class ColShape:
    kind: str                     # 'box' | 'cylinder'
    center: np.ndarray
    size: np.ndarray              # box: full extents ; cylinder: (radius, length, 0)
    axis: str = "z"               # cylinder axis in prop space
    material: str = "PLASTIC_HIGH_DENSITY"

    def world_aabb(self):
        if self.kind == "box":
            h = self.size / 2
            return self.center - h, self.center + h
        r, L = self.size[0], self.size[1]
        ext = {"x": (L / 2, r, r), "y": (r, L / 2, r), "z": (r, r, L / 2)}[self.axis]
        e = np.asarray(ext)
        return self.center - e, self.center + e

    def volume(self):
        if self.kind == "box":
            return float(np.prod(self.size))
        r, L = self.size[0], self.size[1]
        return math.pi * r * r * L

    def inertia_world(self):
        """Per-unit-mass inertia diagonal in prop axes about the shape's own centre."""
        if self.kind == "box":
            x, y, z = self.size
            return np.array([(y * y + z * z) / 12, (x * x + z * z) / 12, (x * x + y * y) / 12])
        r, L = self.size[0], self.size[1]
        ia = r * r / 2
        it = (3 * r * r + L * L) / 12
        return np.array({"x": (ia, it, it), "y": (it, ia, it), "z": (it, it, ia)}[self.axis])


def _bound_common(p, bmin, bmax, center, radius, margin, volume, inertia, mat_index):
    return "\n".join([
        f"{p}<BoxMin {vattr(bmin)} />",
        f"{p}<BoxMax {vattr(bmax)} />",
        f"{p}<BoxCenter {vattr(center)} />",
        f"{p}<SphereCenter {vattr(center)} />",
        f'{p}<SphereRadius value="{f6(radius)}" />',
        f'{p}<Margin value="{f6(margin)}" />',
        f'{p}<Volume value="{volume:.9f}" />',
        f"{p}<Inertia {vattr(inertia)} />",
        f'{p}<MaterialIndex value="{mat_index}" />',
        f'{p}<MaterialColourIndex value="0" />',
        f'{p}<ProceduralID value="0" />',
        f'{p}<RoomID value="0" />',
        f'{p}<PedDensity value="0" />',
        f'{p}<UnkFlags value="0" />',
        f'{p}<PolyFlags value="0" />',
        f'{p}<UnkType value="1" />',
    ])


def _matrix_rows(rows, p):
    return "\n".join(p + " ".join(f6(v) if abs(v) > 1e-12 else "0" for v in r) for r in rows)


def bounds_xml(shapes: list[ColShape]):
    if not shapes:
        raise ValueError("a prop needs at least one collision shape")
    mins, maxs, vols, cgs, inert = [], [], [], [], []
    children = []
    for s in shapes:
        mn, mx = s.world_aabb()
        mins.append(mn)
        maxs.append(mx)
        v = s.volume()
        vols.append(v)
        cgs.append(s.center)
        inert.append(s.inertia_world())
        idx = COL_MATERIALS[s.material]
        if s.kind == "box":
            ext = s.size
            margin = min(0.04, float(ext.min()) / 8)
            radius = float(np.linalg.norm(ext / 2))
            body = _bound_common("        ", mn, mx, s.center, radius, margin, v, s.inertia_world(), idx)
            rows = [(1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)]
            children.append(f'      <Item type="Box">\n{body}\n        <CompositeTransform>\n{_matrix_rows(rows, "        ")}\n'
                            f"        </CompositeTransform>\n        <CompositeFlags1>{COMPOSITE_FLAGS1}</CompositeFlags1>\n"
                            f"        <CompositeFlags2>{COMPOSITE_FLAGS2}</CompositeFlags2>\n      </Item>")
        else:
            r, L = float(s.size[0]), float(s.size[1])
            lmin = np.array([-r, -L / 2, -r])
            lmax = np.array([r, L / 2, r])
            margin = min(0.04, min(r, L / 2) / 4)
            radius = math.sqrt(r * r + (L / 2) ** 2)
            local_inertia = np.array([(3 * r * r + L * L) / 12, r * r / 2, (3 * r * r + L * L) / 12])
            body = _bound_common("        ", lmin, lmax, np.zeros(3), radius, margin, v, local_inertia, idx)
            rot = {"y": [(1, 0, 0), (0, 1, 0), (0, 0, 1)],
                   "z": [(1, 0, 0), (0, 0, 1), (0, -1, 0)],
                   "x": [(0, 1, 0), (1, 0, 0), (0, 0, -1)]}[s.axis]
            c = s.center
            rows = [(*rot[0], 0), (*rot[1], 0), (*rot[2], 0), (c[0], c[1], c[2], 1)]
            children.append(f'      <Item type="Cylinder">\n{body}\n        <CompositeTransform>\n{_matrix_rows(rows, "        ")}\n'
                            f"        </CompositeTransform>\n        <CompositeFlags1>{COMPOSITE_FLAGS1}</CompositeFlags1>\n"
                            f"        <CompositeFlags2>{COMPOSITE_FLAGS2}</CompositeFlags2>\n      </Item>")
    bmin = np.min(mins, axis=0)
    bmax = np.max(maxs, axis=0)
    center = (bmin + bmax) / 2
    total = float(sum(vols))
    cg = np.sum([c * v for c, v in zip(cgs, vols)], axis=0) / max(total, 1e-12)
    I = np.zeros(3)
    for c, v, ii in zip(cgs, vols, inert):
        d = c - cg
        I += v * (ii + np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2]))
    I /= max(total, 1e-12)
    radius = float(np.linalg.norm(bmax - center))
    head = _bound_common("    ", bmin, bmax, center, radius, 0.0, total, I, 0)
    return f'  <Bounds type="Composite">\n{head}\n    <Children>\n' + "\n".join(children) + "\n    </Children>\n  </Bounds>", bmin, bmax


# ---------------------------------------------------------------------------------------------
# drawable
# ---------------------------------------------------------------------------------------------
@dataclass
class ShaderGeom:
    shader: str                   # key of SHADERS
    textures: dict                # param name -> texture name
    params: dict                  # param name -> tuple overrides
    pos: np.ndarray
    nrm: np.ndarray
    uv: np.ndarray
    tan: np.ndarray | None
    idx: np.ndarray               # (m,3)
    color: np.ndarray | None = None  # (n,4) uint8 vertex colours
    extra: dict = field(default_factory=dict)


def _shader_xml(sg: ShaderGeom):
    fname, bucket, plist = SHADERS[sg.shader]
    items = []
    for pname, default in plist:
        if default == "tex":
            items.append(f'          <Item name="{pname}" type="Texture">\n            <Name>{sg.textures[pname]}</Name>\n          </Item>')
        else:
            v = tuple(sg.params.get(pname, default))
            v = v + (0,) * (4 - len(v))
            items.append(f'          <Item name="{pname}" type="Vector" x="{v[0]:g}" y="{v[1]:g}" z="{v[2]:g}" w="{v[3]:g}" />')
    return (f"      <Item>\n        <Name>{fname[:-4]}</Name>\n        <FileName>{fname}</FileName>\n"
            f'        <RenderBucket value="{bucket}" />\n        <Parameters>\n' + "\n".join(items) +
            "\n        </Parameters>\n      </Item>")


def _texture_xml(name, usage, w, h, mips, fmt):
    return (f"      <Item>\n        <Name>{name}</Name>\n        <Unk32 value=\"0\" />\n        <Usage>{usage}</Usage>\n"
            f"        <UsageFlags>UNK24</UsageFlags>\n        <ExtraFlags value=\"0\" />\n        <Width value=\"{w}\" />\n"
            f"        <Height value=\"{h}\" />\n        <MipLevels value=\"{mips}\" />\n        <Format>{fmt}</Format>\n"
            f"        <FileName>{name}.dds</FileName>\n      </Item>")


def _split(sg: ShaderGeom, limit=60000):
    """Yield (pos, nrm, uv, tan, col, idx) chunks with < limit vertices each."""
    n = len(sg.pos)
    if n <= limit:
        yield sg.pos, sg.nrm, sg.uv, sg.tan, sg.color, sg.idx
        return
    tris = sg.idx
    start = 0
    while start < len(tris):
        used = {}
        out = []
        k = start
        while k < len(tris):
            t = tris[k]
            new = sum(1 for v in t if v not in used)
            if len(used) + new > limit:
                break
            for v in t:
                if v not in used:
                    used[v] = len(used)
            out.append([used[v] for v in t])
            k += 1
        order = np.array(sorted(used, key=used.get))
        yield (sg.pos[order], sg.nrm[order], sg.uv[order], None if sg.tan is None else sg.tan[order],
               None if sg.color is None else sg.color[order], np.asarray(out))
        start = k


def drawable_xml(name, geoms: list[ShaderGeom], textures: list, shapes: list[ColShape], lod_dist=9998.0):
    """textures: list of (name, usage, w, h, mips, fmt)."""
    allp = np.concatenate([g.pos for g in geoms])
    bmin, bmax = allp.min(axis=0), allp.max(axis=0)
    center = (bmin + bmax) / 2
    radius = float(np.linalg.norm(allp - center, axis=1).max())
    shader_items = "\n".join(_shader_xml(g) for g in geoms)
    tex_items = "\n".join(_texture_xml(*t) for t in textures)
    geo_items = []
    for si, g in enumerate(geoms):
        tangent = g.shader in TANGENT_SHADERS
        for pos, nrm, uv, tan, col, idx in _split(g):
            gmin, gmax = pos.min(axis=0), pos.max(axis=0)
            if col is None:
                col = np.full((len(pos), 4), 255, np.uint8)
            rows = []
            for i in range(len(pos)):
                parts = [f"{f6(pos[i, 0])} {f6(pos[i, 1])} {f6(pos[i, 2])}",
                         f"{f6(nrm[i, 0])} {f6(nrm[i, 1])} {f6(nrm[i, 2])}",
                         f"{col[i, 0]} {col[i, 1]} {col[i, 2]} {col[i, 3]}",
                         f"{f6(uv[i, 0])} {f6(uv[i, 1])}"]
                if tangent:
                    parts.append(f"{f6(tan[i, 0])} {f6(tan[i, 1])} {f6(tan[i, 2])} {f6(tan[i, 3])}")
                rows.append("              " + "   ".join(parts))
            flat = idx.reshape(-1)
            ilines = ["              " + " ".join(str(int(k)) for k in flat[i:i + 24]) for i in range(0, len(flat), 24)]
            layout = "                <Position />\n                <Normal />\n                <Colour0 />\n                <TexCoord0 />"
            if tangent:
                layout += "\n                <Tangent />"
            geo_items.append(
                f"        <Item>\n          <ShaderIndex value=\"{si}\" />\n"
                f"          <BoundingBoxMin {vattr(gmin)} w=\"0\" />\n          <BoundingBoxMax {vattr(gmax)} w=\"0\" />\n"
                f"          <VertexBuffer>\n            <Flags value=\"0\" />\n            <Layout type=\"GTAV1\">\n{layout}\n            </Layout>\n"
                f"            <Data>\n" + "\n".join(rows) + "\n            </Data>\n          </VertexBuffer>\n"
                f"          <IndexBuffer>\n            <Data>\n" + "\n".join(ilines) + "\n            </Data>\n          </IndexBuffer>\n        </Item>")
    bxml, cmin, cmax = bounds_xml(shapes)
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
  <Name>{name}</Name>
  <BoundingSphereCenter {vattr(center)} />
  <BoundingSphereRadius value="{f6(radius)}" />
  <BoundingBoxMin {vattr(bmin)} />
  <BoundingBoxMax {vattr(bmax)} />
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
    <Shaders>
{shader_items}
    </Shaders>
  </ShaderGroup>
  <DrawableModelsHigh>
    <Item>
      <RenderMask value="255" />
      <Flags value="0" />
      <HasSkin value="0" />
      <BoneIndex value="0" />
      <Unknown1 value="0" />
      <Geometries>
{chr(10).join(geo_items)}
      </Geometries>
    </Item>
  </DrawableModelsHigh>
{bxml}
</Drawable>
"""
    return xml, (bmin, bmax, center, radius), (cmin, cmax)


# ---------------------------------------------------------------------------------------------
# archetypes
# ---------------------------------------------------------------------------------------------
def archetype_xml(name, bmin, bmax, center, radius, lod_dist, flags, hd_dist):
    return f"""    <Item type="CBaseArchetypeDef">
      <lodDist value="{lod_dist:g}" />
      <flags value="{int(flags)}" />
      <specialAttribute value="0" />
      <bbMin {vattr(bmin)} />
      <bbMax {vattr(bmax)} />
      <bsCentre {vattr(center)} />
      <bsRadius value="{f6(radius)}" />
      <hdTextureDist value="{hd_dist:g}" />
      <name>{name}</name>
      <textureDictionary />
      <clipDictionary />
      <drawableDictionary />
      <physicsDictionary />
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{name}</assetName>
      <extensions />
    </Item>"""


def ytyp_xml(ytyp_name, archetypes: list[str]):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<CMapTypes>
  <extensions />
  <archetypes>
{chr(10).join(archetypes)}
  </archetypes>
  <name>{ytyp_name}</name>
  <dependencies />
  <compositeEntityTypes />
</CMapTypes>
"""
