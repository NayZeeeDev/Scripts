"""
propkit - write GTA V props as CodeWalker XML (+ textures) from Python.

    mesh = Mesh()
    ...add triangles / quads...
    write_prop("out/", "nz_thing", [mesh], texture_image, collision=True)
    write_ytyp("out/", "nz_things", {"nz_thing": mesh_bounds})

Produces <name>.ydr.xml with a <name>/ texture folder beside it, the layout
CodeWalker's "Import XML" expects. tools/cwbuild turns them into .ydr/.ytyp.

Axes are GTA's: Z up, +Y forward, metres. UVs are top-down (DirectX).
Triangles wind counter-clockwise seen from outside.
"""

import io
import math
import os
import struct

from PIL import Image


# --------------------------------------------------------------------------- mesh

class Mesh:
    def __init__(self):
        self.pos, self.nrm, self.uv, self.idx = [], [], [], []

    def vertex(self, p, n, uv):
        self.pos.append(tuple(p))
        self.nrm.append(tuple(n))
        self.uv.append(tuple(uv))
        return len(self.pos) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    def extend(self, other, transform=None):
        base = len(self.pos)
        for p, n, t in zip(other.pos, other.nrm, other.uv):
            if transform:
                p, n = transform(p, n)
            self.vertex(p, n, t)
        self.idx += [i + base for i in other.idx]

    def bounds(self):
        xs, ys, zs = zip(*self.pos)
        lo, hi = (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))
        c = tuple((lo[i] + hi[i]) / 2 for i in range(3))
        r = math.sqrt(sum((hi[i] - c[i]) ** 2 for i in range(3)))
        return lo, hi, c, r


def norm(v):
    l = math.sqrt(sum(x * x for x in v)) or 1.0
    return tuple(x / l for x in v)


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def rotate_z(deg, offset=(0, 0, 0)):
    s, c = math.sin(math.radians(deg)), math.cos(math.radians(deg))

    def tf(p, n):
        rp = (p[0] * c - p[1] * s + offset[0], p[0] * s + p[1] * c + offset[1], p[2] + offset[2])
        rn = (n[0] * c - n[1] * s, n[0] * s + n[1] * c, n[2])
        return rp, rn
    return tf


# ------------------------------------------------------------------------ texture

def dds_dxt5(img):
    """Image -> DXT5 .dds bytes with a full mip chain (Pillow encodes each level)."""
    img = img.convert("RGBA")
    w, h = img.size
    assert w == h and (w & (w - 1)) == 0, "texture must be square power of two"
    levels, size = [], w
    while size >= 4:
        lvl = img if size == w else img.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        lvl.save(buf, format="DDS", pixel_format="DXT5")
        data = buf.getvalue()
        assert data[84:88] == b"DXT5"
        levels.append(data[128:])
        size //= 2
    header = bytearray(128)
    struct.pack_into("<4sIIIIIII", header, 0, b"DDS ", 124,
                     0x1 | 0x2 | 0x4 | 0x1000 | 0x80000 | 0x20000, h, w, len(levels[0]), 0, len(levels))
    struct.pack_into("<II4s", header, 76, 32, 0x4, b"DXT5")
    struct.pack_into("<I", header, 108, 0x1000 | 0x8 | 0x400000)
    return bytes(header) + b"".join(levels), len(levels)


# ---------------------------------------------------------------------------- xml

def f(v):
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def v3(tag, p):
    return f'<{tag} x="{f(p[0])}" y="{f(p[1])}" z="{f(p[2])}" />'


SHADER = """   <Shaders>
    <Item>
     <Name>default</Name>
     <FileName>default.sps</FileName>
     <RenderBucket value="0" />
     <Parameters>
      <Item name="DiffuseSampler" type="Texture">
       <Name>{tex}</Name>
      </Item>
      <Item name="matMaterialColorScale" type="Vector" x="1" y="0" z="0" w="1" />
      <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
      <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
      <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
      <Item name="globalAnimUV0" type="Vector" x="1" y="0" z="0" w="0" />
      <Item name="globalAnimUV1" type="Vector" x="0" y="1" z="0" w="0" />
     </Parameters>
    </Item>
   </Shaders>"""

TEXTURE = """   <TextureDictionary>
    <Item>
     <Name>{tex}</Name>
     <Unk32 value="128" />
     <Usage>DIFFUSE</Usage>
     <UsageFlags>UNK24</UsageFlags>
     <ExtraFlags value="0" />
     <Width value="{w}" />
     <Height value="{w}" />
     <MipLevels value="{mips}" />
     <Format>D3DFMT_DXT5</Format>
     <FileName>{tex}.dds</FileName>
    </Item>
   </TextureDictionary>"""


def collision_xml(lo, hi, c, r):
    size = [hi[i] - lo[i] for i in range(3)]
    vol = size[0] * size[1] * size[2]
    inertia = ((size[1] ** 2 + size[2] ** 2) / 12, (size[0] ** 2 + size[2] ** 2) / 12, (size[0] ** 2 + size[1] ** 2) / 12)

    def common(ind):
        return "\n".join(ind + l for l in [
            v3("BoxMin", lo), v3("BoxMax", hi), v3("BoxCenter", c), v3("SphereCenter", c),
            f'<SphereRadius value="{f(r)}" />', '<Margin value="0.005" />', f'<Volume value="{f(vol)}" />',
            v3("Inertia", inertia), '<MaterialIndex value="0" />', '<MaterialColourIndex value="0" />',
            '<ProceduralID value="0" />', '<RoomID value="0" />', '<PedDensity value="0" />',
            '<UnkFlags value="0" />', '<PolyFlags value="0" />', '<UnkType value="1" />'])
    return f""" <Bounds type="Composite">
{common('  ')}
  <Children>
   <Item type="Box">
{common('    ')}
    <CompositeTransform>
     1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1
    </CompositeTransform>
    <CompositeFlags1>MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE</CompositeFlags1>
    <CompositeFlags2>VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS</CompositeFlags2>
   </Item>
  </Children>
 </Bounds>
"""


def write_prop(out_dir, name, mesh, texture, collision=False):
    """Writes <out_dir>/<name>.ydr.xml and <out_dir>/<name>/<name>_d.dds."""
    os.makedirs(os.path.join(out_dir, name), exist_ok=True)
    tex = name + "_d"
    dds, mips = dds_dxt5(texture)
    with open(os.path.join(out_dir, name, tex + ".dds"), "wb") as fh:
        fh.write(dds)

    lo, hi, c, r = mesh.bounds()
    rows = "\n".join(
        "          {}   {}   255 255 255 255   {}".format(
            " ".join(f(x) for x in p), " ".join(f(x) for x in n), " ".join(f(x) for x in t))
        for p, n, t in zip(mesh.pos, mesh.nrm, mesh.uv))
    idx = "\n".join("          " + " ".join(str(i) for i in mesh.idx[k:k + 24])
                    for k in range(0, len(mesh.idx), 24))
    assert len(mesh.pos) < 65536, "too many vertices for one geometry"

    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
 <Name>{name}</Name>
 {v3('BoundingSphereCenter', c)}
 <BoundingSphereRadius value="{f(r)}" />
 {v3('BoundingBoxMin', lo)}
 {v3('BoundingBoxMax', hi)}
 <LodDistHigh value="9998" />
 <LodDistMed value="9998" />
 <LodDistLow value="9998" />
 <LodDistVlow value="9998" />
 <FlagsHigh value="1" />
 <FlagsMed value="0" />
 <FlagsLow value="0" />
 <FlagsVlow value="0" />
 <ShaderGroup>
{TEXTURE.format(tex=tex, w=texture.size[0], mips=mips)}
{SHADER.format(tex=tex)}
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
     <BoundingBoxMin x="{f(lo[0])}" y="{f(lo[1])}" z="{f(lo[2])}" w="0" />
     <BoundingBoxMax x="{f(hi[0])}" y="{f(hi[1])}" z="{f(hi[2])}" w="0" />
     <VertexBuffer>
      <Flags value="0" />
      <Layout type="GTAV1">
       <Position />
       <Normal />
       <Colour0 />
       <TexCoord0 />
      </Layout>
      <Data>
{rows}
      </Data>
     </VertexBuffer>
     <IndexBuffer>
      <Data>
{idx}
      </Data>
     </IndexBuffer>
    </Item>
   </Geometries>
  </Item>
 </DrawableModelsHigh>
{collision_xml(lo, hi, c, r) if collision else ''}</Drawable>
"""
    with open(os.path.join(out_dir, name + ".ydr.xml"), "w", newline="\n") as fh:
        fh.write(xml)


def write_ytyp(out_dir, ytyp_name, archetypes, lod=100.0):
    """archetypes: {name: Mesh}. Textures are embedded, so no txd is set."""
    items = []
    for name, mesh in archetypes.items():
        lo, hi, c, r = mesh.bounds()
        items.append(f"""    <Item type="CBaseArchetypeDef">
      <lodDist value="{f(lod)}"/>
      <flags value="32"/>
      <specialAttribute value="0"/>
      <bbMin x="{f(lo[0])}" y="{f(lo[1])}" z="{f(lo[2])}"/>
      <bbMax x="{f(hi[0])}" y="{f(hi[1])}" z="{f(hi[2])}"/>
      <bsCentre x="{f(c[0])}" y="{f(c[1])}" z="{f(c[2])}"/>
      <bsRadius value="{f(r)}"/>
      <hdTextureDist value="50"/>
      <name>{name}</name>
      <textureDictionary/>
      <clipDictionary/>
      <drawableDictionary/>
      <physicsDictionary/>
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{name}</assetName>
      <extensions/>
    </Item>""")
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<CMapTypes>\n  <extensions/>\n  <archetypes>\n'
           + "\n".join(items) + f"\n  </archetypes>\n  <name>{ytyp_name}</name>\n  <dependencies/>\n"
           "  <compositeEntityTypes/>\n</CMapTypes>\n")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, ytyp_name + ".ytyp.xml"), "w", newline="\n") as fh:
        fh.write(xml)


def write_obj(path, mesh, texture_file):
    """Preview copy for Blender/three.js (OBJ UVs are bottom-up, so V flips)."""
    mtl = os.path.splitext(path)[0] + ".mtl"
    with open(mtl, "w", newline="\n") as fh:
        fh.write(f"newmtl m\nKd 1 1 1\nmap_Kd {texture_file}\n")
    with open(path, "w", newline="\n") as fh:
        fh.write(f"mtllib {os.path.basename(mtl)}\no prop\n")
        for p in mesh.pos:
            fh.write("v {:.5f} {:.5f} {:.5f}\n".format(*p))
        for t in mesh.uv:
            fh.write("vt {:.5f} {:.5f}\n".format(t[0], 1 - t[1]))
        for n in mesh.nrm:
            fh.write("vn {:.4f} {:.4f} {:.4f}\n".format(*n))
        fh.write("usemtl m\n")
        for k in range(0, len(mesh.idx), 3):
            a, b, c = (i + 1 for i in mesh.idx[k:k + 3])
            fh.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")
